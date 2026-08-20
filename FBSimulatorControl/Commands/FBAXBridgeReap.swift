/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
@preconcurrency import FBControlCore
import Foundation

/// Where a persistent bridge's socket lives, and how to recognise one.
///
/// Shared by the transport that creates them and the reaper that collects them, because a reaper that
/// disagreed with the transport about the naming would either miss every orphan or delete something
/// that was never ours.
enum FBAXBridgeSocket {
  static let directory = "/tmp"
  static let prefix = "idb_axbridge_"
  static let suffix = ".sock"

  /// The backlog the guest's `serve` loop listens with, mirrored here because the reaper's classification
  /// depends on it.
  ///
  /// The probe reads a refused connection as "nothing is bound, the file is stale" and deletes the
  /// socket. That is only safe while a live guest still has a queue slot to accept the probe into: on BSD
  /// a connect to a Unix socket whose backlog is full fails with `ECONNREFUSED`, which is the same errno
  /// as nothing listening. The serve loop only ever handles one client at a time, so the backlog exists
  /// purely to keep a probe from being refused while somebody else is connected. Pinned guest-side by
  /// `AccessibilityServiceTests`.
  static let guestListenBacklog: Int32 = 16

  static func path(forConnection identifier: String) -> String {
    "\(directory)/\(prefix)\(identifier)\(suffix)"
  }

  /// Every path that looks like a bridge socket, whether or not anything is still listening on it.
  ///
  /// Joined through a URL so a trailing or doubled separator in the caller's directory does not reach
  /// the socket path. Deliberately not `standardizedFileURL`: that resolves symlinks, and on macOS
  /// `/tmp` is one — a caller that asked about `/tmp` should be told about `/tmp`, not `/private/tmp`.
  static func existingPaths(inDirectory directory: String = Self.directory) -> [String] {
    let base = URL(fileURLWithPath: directory, isDirectory: true)
    let contents =
      (try? FileManager.default.contentsOfDirectory(
        at: base, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]
      )) ?? []
    // Re-joined onto the caller's own directory string rather than using the enumerated URL's path:
    // `FileManager` hands back resolved URLs, and answering `/private/tmp` to someone who asked about
    // `/tmp` makes the summary hard to match against what they passed in.
    let trimmed = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
    return
      contents
      .map(\.lastPathComponent)
      .filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }
      .sorted()
      .map { "\(trimmed)/\($0)" }
  }
}

/// What a reap did, per socket.
public struct FBAXBridgeReapSummary: Sendable, Equatable {
  /// Guests that answered the shutdown and are exiting.
  public let shutDown: [String]
  /// Socket files whose guest was already gone, removed here.
  public let removedStaleSockets: [String]
  /// Guests that did not answer within the probe window, left alone — see `FBAXBridgeReap`.
  public let busy: [String]
  /// Guests that answered — so they are provably idle — but rejected the shutdown verb, which means
  /// they were built before it existed. Nothing here can be collected until the host that spawns them
  /// is rebuilt; they are reported separately from `busy` because they are not busy.
  public let unreapable: [String]

  public var isEmpty: Bool {
    shutDown.isEmpty && removedStaleSockets.isEmpty && busy.isEmpty && unreapable.isEmpty
  }
}

/// Collects persistent bridge guests that no host is talking to.
///
/// A `serve` guest is parented to `launchd_sim` rather than to the host, so a host that dies without
/// running its teardown — killed, crashed, or restarted — leaves the guest running. It exits on its own
/// after an idle timeout, which is fine for a host that stops for good and useless for one that restarts
/// inside that window: each restart strands another guest, and they accumulate for as long as the
/// iteration loop is faster than the timeout.
///
/// **Why answering is proof that a guest is idle.** The serve loop accepts one client at a time and
/// stays inside that connection until the client goes away, so while a host is attached nothing else is
/// accepted. A probe that gets *answered* was therefore accepted, which means no host was attached — the
/// guest is an orphan. A probe that goes unanswered is a guest with a live client, and is left alone.
/// The reaper needs no inventory of who is using what, and cannot take a bridge out from under a
/// running session.
public enum FBAXBridgeReap {

  /// Long enough that a healthy free guest always answers (it replies without binding the runtime), and
  /// short enough that a directory of busy guests does not make a reap take minutes.
  public static let defaultProbeTimeout: TimeInterval = 2

  /// Shuts down every bridge guest that no host is connected to, and removes the socket files of guests
  /// that are already gone.
  ///
  /// Safe to call at any time, including while other sessions are reading — see the note above on why a
  /// busy guest cannot be reaped by mistake.
  @discardableResult
  public static func reapIdleGuests(
    inDirectory directory: String = "/tmp",
    probeTimeout: TimeInterval = defaultProbeTimeout,
    logger: (any FBControlCoreLogger)? = nil
  ) -> FBAXBridgeReapSummary {
    var shutDown: [String] = []
    var removed: [String] = []
    var busy: [String] = []
    var unreapable: [String] = []

    for path in FBAXBridgeSocket.existingPaths(inDirectory: directory) {
      switch probe(path: path, timeout: probeTimeout) {
      case .shutDown:
        logger?.log("Reaped idle axbridge guest on \(path)")
        shutDown.append(path)
      case .unreachable:
        // Nothing is listening, so the file is the only thing left of a guest that has already gone.
        unlink(path)
        logger?.log("Removed stale axbridge socket \(path)")
        removed.append(path)
      case .busy:
        busy.append(path)
      case .unreapable:
        logger?.log("Idle axbridge guest on \(path) predates the shutdown verb and cannot be collected")
        unreapable.append(path)
      }
    }
    return FBAXBridgeReapSummary(
      shutDown: shutDown, removedStaleSockets: removed, busy: busy, unreapable: unreapable
    )
  }

  private enum Outcome {
    case shutDown
    case unreachable
    case busy
    case unreapable
  }

  private static func probe(path: String, timeout: TimeInterval) -> Outcome {
    let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fileDescriptor >= 0 else {
      return .busy
    }
    defer { close(fileDescriptor) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let size = MemoryLayout.size(ofValue: address.sun_path)
    guard path.utf8.count < size else {
      return .busy
    }
    _ = withUnsafeMutablePointer(to: &address.sun_path) { raw in
      path.withCString { source in
        strncpy(UnsafeMutableRawPointer(raw).assumingMemoryBound(to: CChar.self), source, size - 1)
      }
    }
    let connected = withUnsafePointer(to: &address) { raw in
      raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
        Darwin.connect(fileDescriptor, pointer, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
      }
    }
    guard connected else {
      return .unreachable
    }

    // Bound the wait: an unanswered probe is the signal that another host holds this guest, so it must
    // cost the probe window rather than the transport's much longer round-trip deadline.
    var noSigPipe: Int32 = 1
    setsockopt(fileDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
    var window = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000))
    setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &window, socklen_t(MemoryLayout<timeval>.size))

    let request: [String: Any] = [FBAXWire.Request.verb.rawValue: FBAXWire.Verb.shutdown.rawValue]
    guard let payload = try? JSONSerialization.data(withJSONObject: request) else {
      return .busy
    }
    do {
      try FBAXBridgeConnection.writeFrame(fileDescriptor, payload)
      let response = try FBAXBridgeConnection.readFrame(fileDescriptor, guest: nil)
      let parsed = try? JSONSerialization.jsonObject(with: response) as? [String: Any]
      if (parsed?["shutdown"] as? Bool) == true {
        return .shutDown
      }
      // It answered, so it accepted us, so it is idle — it just does not know the verb. Reporting that
      // as busy would send someone hunting a client that is not there.
      return .unreapable
    } catch {
      // Connected but never served: the guest has a client already, so this is somebody else's bridge.
      return .busy
    }
  }
}

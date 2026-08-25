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
  static let suffix = ".sock"

  /// A directory of our own beneath the per-user temporary directory, owner-only.
  ///
  /// Private rather than `/tmp` for two reasons: the reaper probes and unlinks whatever it finds here,
  /// which it should only ever do to a directory it owns; and a socket name anyone can predict is only
  /// safe if nobody else can bind it first.
  ///
  /// Owning the directory is also what pays for the name. `sun_path` is 104 bytes and the per-user
  /// temporary directory is 49 of them, so the old `idb_axbridge_` prefix plus a UUID no longer fits —
  /// but the prefix only existed to pick our sockets out of a directory full of other people's files,
  /// and here there are none.
  static let directory: String = {
    let base = userTemporaryDirectory()
    return "\(base.hasSuffix("/") ? String(base.dropLast()) : base)/idb-ax"
  }()

  /// The per-user temporary directory, from `confstr` rather than `$TMPDIR`.
  ///
  /// `NSTemporaryDirectory()` reads the environment variable, which a build system, CI harness or
  /// sandbox is free to set to anything. That is wrong here three times over: an arbitrary value can
  /// overrun `sun_path`, it could point somewhere world-writable, and — worst, because it fails
  /// silently — two host processes that disagree about the path would each spawn their own guest
  /// instead of sharing one, losing the reuse with no error to notice. `confstr` answers from the uid,
  /// so every process this user runs gets the same fixed-length answer.
  private static func userTemporaryDirectory() -> String {
    let size = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
    guard size > 0 else {
      return "/tmp"
    }
    var buffer = [CChar](repeating: 0, count: size)
    guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, size) == size else {
      return "/tmp"
    }
    // `confstr` reports a size that includes the terminator, which has to come off before decoding.
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }

  /// Creates the socket directory if it is not already there, and makes sure it is owner-only. Called
  /// before a spawn, because the guest binds into it and `bind` does not create intermediate
  /// directories.
  ///
  /// The mode is applied after the fact rather than left to `createDirectory`, which honours its
  /// `attributes` only when it actually creates something. That distinction matters on the `/tmp`
  /// fallback: `/tmp` is world-writable, so another local user could pre-create `idb-ax` there with a
  /// permissive mode, and a create call would return success on it without complaint — handing them a
  /// directory we then bind predictable socket names into. Setting the mode every time closes that,
  /// and throwing if it cannot be set fails closed rather than serving from a directory we do not
  /// actually control.
  static func prepareDirectory(_ path: String = directory) throws {
    let manager = FileManager.default
    try manager.createDirectory(
      atPath: path,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: ownerOnlyPermissions]
    )
    try manager.setAttributes([.posixPermissions: ownerOnlyPermissions], ofItemAtPath: path)
  }

  /// `rwx` for the owner and nothing for anyone else.
  static let ownerOnlyPermissions = 0o700

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
    "\(directory)/\(identifier)\(suffix)"
  }

  /// The socket a bridge serving `udid` listens on.
  ///
  /// Named for the simulator rather than the connection, so a process can find a bridge it did not
  /// start. Case is normalised because a UDID is hex that can reach two callers in either case, and both
  /// must compute the same socket. Dashes are stripped to buy length: ten bytes spare in `sun_path`
  /// rather than six, which matters because `bind` truncates an over-long path and reports success.
  static func path(forSimulator udid: String) -> String {
    path(forConnection: udid.replacingOccurrences(of: "-", with: "").uppercased())
  }

  /// Every path that looks like a bridge socket, whether or not anything is still listening on it.
  ///
  /// The suffix is the whole test, because the directory is ours and holds nothing else. It used to
  /// also require a filename prefix, which was how our sockets were told apart from everything else in
  /// a shared `/tmp`.
  ///
  /// Joined through a URL so a trailing or doubled separator in the caller's directory does not reach
  /// the socket path. Deliberately not `standardizedFileURL`: that resolves symlinks, so a caller who
  /// asked about a path should be told about that path, not its resolved form.
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
      .filter { $0.hasSuffix(suffix) }
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
  /// `nil` means the directory the transport spawns guests into, which is the only one a caller outside
  /// this module can name — `FBAXBridgeSocket` is internal, so it cannot be spelled as a default here.
  @discardableResult
  public static func reapIdleGuests(
    inDirectory directory: String? = nil,
    probeTimeout: TimeInterval = defaultProbeTimeout,
    logger: (any FBControlCoreLogger)? = nil
  ) -> FBAXBridgeReapSummary {
    let directory = directory ?? FBAXBridgeSocket.directory
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

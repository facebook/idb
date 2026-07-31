/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
@preconcurrency import FBControlCore
import Foundation

/// How `FBAXBridgeUIAutomation` obtains an app's attribute tree from the guest `accessibility`
/// service. The verb logic in the conformer is transport-agnostic; only the mechanism differs:
///
/// - `FBAXBridgeOneshotTransport` spawns the guest per read (`accessibility describe`), simple but
///   pays the ~610ms spawn+dlopen cost every read.
/// - `FBAXBridgePersistentTransport` spawns the guest once (`accessibility serve <socket>`) and reads
///   over a reused Unix-domain socket, so warm reads are ~20ms (~30x faster) — the path a long-lived
///   host process (companion, `ui shell`, a streaming hit-test server) should use.
///
/// `read` returns the guest's raw JSON response bytes (a `Sendable` `Data`, so it crosses the actor
/// boundary cleanly); the conformer parses the `{ "ok", "tree" | "error" }` envelope.
protocol FBAXBridgeTransport {
  /// Reads the whole element tree for `pid` (the guest `describe` verb), bounded by the caller's
  /// depth and node budget — the host owns those bounds so both XCUI-grade backends truncate alike.
  func read(pid: pid_t, maxDepth: Int, maxNodes: Int) async throws -> Data
  /// Reads just the element at a point for `pid` (the guest `hittest` verb) — one round-trip, no walk.
  func hitTest(pid: pid_t, x: Double, y: Double) async throws -> Data
}

/// Parses the guest's `{ "ok": Bool, "tree": {...} | "error": String }` response envelope.
enum FBAXBridgeResponse {
  /// Parses the guest JSON and validates its `ok`/error framing, returning the top-level response
  /// dictionary of a successful response. A failed response (`{ ok: false, error }`) throws: the typed
  /// dead-pid case for `application_unavailable` (so the conformer re-raises the backend-neutral
  /// `FBUIAutomationError.applicationUnavailable`, matching the remote backend), otherwise an opaque
  /// `guestFailure` carrying the guest's own message.
  private static func validatedResponse(fromResponse data: Data, pid: pid_t) throws -> [String: Any] {
    guard let object = try? JSONSerialization.jsonObject(with: data), let response = object as? [String: Any] else {
      throw FBAXBridgeError.guestFailure("pid \(pid): unparseable guest response")
    }
    guard (response["ok"] as? Bool) == true else {
      if (response["error_kind"] as? String) == "application_unavailable" {
        throw FBAXBridgeError.applicationUnavailable(pid: pid)
      }
      let message = (response["error"] as? String) ?? "the guest reported a failure with no message"
      throw FBAXBridgeError.guestFailure("pid \(pid): \(message)")
    }
    return response
  }

  /// The node a successful response carries, or `nil` for a successful *empty* result
  /// (`{ ok: true, empty: true }`) — which only a hit-test produces.
  private static func node(fromValidatedResponse response: [String: Any], pid: pid_t) throws -> [String: Any]? {
    if (response["empty"] as? Bool) == true {
      return nil
    }
    guard let tree = response["tree"] as? [String: Any] else {
      throw FBAXBridgeError.guestFailure("pid \(pid): ok response without a tree or empty flag")
    }
    return tree
  }

  /// Parses a whole-tree read: the tree, plus whether the guest's walk was cut short by the depth or
  /// node bound (so the caller can warn the tree is incomplete). A tree read has no empty result — an
  /// app always has a root element — so an empty response is a protocol violation rather than "nothing
  /// there". `truncated` defaults to `false` when the guest omits it (an older guest, or a complete walk).
  static func tree(fromResponse data: Data, pid: pid_t) throws -> (tree: [String: Any], truncated: Bool) {
    let response = try validatedResponse(fromResponse: data, pid: pid)
    guard let tree = try node(fromValidatedResponse: response, pid: pid) else {
      throw FBAXBridgeError.guestFailure("pid \(pid): empty response to a whole-tree read")
    }
    let truncated = (response["truncated"] as? Bool) ?? false
    return (tree, truncated)
  }

  /// Parses a hit-test response: the hit node, or `nil` when the guest reports no element at the point
  /// — a valid empty result. A failure throws, so a caller can tell empty space from a broken reader.
  static func hitTest(fromResponse data: Data, pid: pid_t) throws -> [String: Any]? {
    let response = try validatedResponse(fromResponse: data, pid: pid)
    return try node(fromValidatedResponse: response, pid: pid)
  }
}

// MARK: - One-shot transport

/// Spawns the guest once per read and returns its stdout JSON.
struct FBAXBridgeOneshotTransport: FBAXBridgeTransport {
  let simulator: FBSimulator

  func read(pid: pid_t, maxDepth: Int, maxNodes: Int) async throws -> Data {
    try await spawn(["accessibility", "describe", "--pid", "\(pid)", "--max-depth", "\(maxDepth)", "--max-nodes", "\(maxNodes)"])
  }

  func hitTest(pid: pid_t, x: Double, y: Double) async throws -> Data {
    try await spawn(["accessibility", "hittest", "--pid", "\(pid)", "--x", "\(x)", "--y", "\(y)"])
  }

  private func spawn(_ arguments: [String]) async throws -> Data {
    guard let helperPath = BundledResources.path(forItem: "SimulatorFrameworkBridge") else {
      throw FBAXBridgeError.bridgeUnavailable
    }
    let output = try await simulator.launchProcessConsumingOutput(launchPath: helperPath, arguments: arguments)
    guard !output.stdout.isEmpty else {
      let stderr = String(data: output.stderr, encoding: .utf8) ?? ""
      throw FBAXBridgeError.guestFailure("exit \(output.exitCode); no output. stderr: \(stderr)")
    }
    return output.stdout
  }
}

// MARK: - Persistent transport

/// Spawns `accessibility serve <socket>` once and reads over a reused Unix-domain socket. An actor so
/// the connection is established exactly once under concurrent callers, and reads are serialized (the
/// guest handles one request at a time). Memoized per simulator via `commandCache`, so a long-lived
/// host process amortizes the spawn+warmup across every read.
actor FBAXBridgePersistentTransport: FBAXBridgeTransport {
  private weak var simulator: FBSimulator?
  private var connectionTask: Task<FBAXBridgeConnection, Error>?
  private var connectionGeneration = 0

  init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  func read(pid: pid_t, maxDepth: Int, maxNodes: Int) async throws -> Data {
    try await roundTripWithRecovery(["verb": "describe", "pid": Int(pid), "maxDepth": maxDepth, "maxNodes": maxNodes])
  }

  func hitTest(pid: pid_t, x: Double, y: Double) async throws -> Data {
    try await roundTripWithRecovery(["verb": "hittest", "pid": Int(pid), "x": x, "y": y])
  }

  /// Sends one request over the reused connection, recovering from a terminated serve process.
  private func roundTripWithRecovery(_ request: [String: Any]) async throws -> Data {
    let requestData = try JSONSerialization.data(withJSONObject: request)
    do {
      let (connection, generation) = try await self.connection()
      do {
        return try await connection.roundTrip(requestData)
      } catch {
        // Compare-and-clear: drop the memoized connection only if it is still the generation that just
        // failed. `read` is reentrant on the actor (it suspends at every `await`), so a concurrent read
        // that shared this now-dead connection may already have dropped it and established a fresh serve
        // (a newer generation); clearing unconditionally would evict that healthy connection from the
        // memo and spawn a redundant serve process (the orphan is later SIGKILLed).
        if connectionGeneration == generation {
          connectionTask = nil
        }
        throw error
      }
    } catch {
      // The connection is likely dead — the serve process terminated (crash, sim teardown, external
      // kill), or the stream desynced after a partial frame. It has been dropped above; re-establish a
      // fresh serve + socket and retry the request once. The transport is itself memoized per simulator
      // (`commandCache`) and never re-created for the target's lifetime, so without this a terminated
      // SimulatorFrameworkBridge would wedge the client (every future request reusing the dead fd).
      // Retrying makes recovery transparent; a second failure (e.g. the app's accessibility server is
      // genuinely down) is surfaced.
      let (connection, _) = try await self.connection()
      return try await connection.roundTrip(requestData)
    }
  }

  /// Returns the memoized connection along with the generation that produced it, so a caller can
  /// compare-and-clear on the exact generation that failed (`read` is reentrant on the actor — the
  /// generation is captured before any `await`, so a reentrant caller that re-establishes bumps it and
  /// the failing caller correctly skips the clear). Establishes once under concurrent callers; each
  /// fresh serve is a new generation, and an establish failure clears the memo so a later call retries.
  private func connection() async throws -> (connection: FBAXBridgeConnection, generation: Int) {
    if let connectionTask {
      let generation = connectionGeneration
      return (try await connectionTask.value, generation)
    }
    connectionGeneration += 1
    let generation = connectionGeneration
    let simulator = self.simulator
    let task = Task { try await Self.establish(simulator: simulator) }
    connectionTask = task
    do {
      return (try await task.value, generation)
    } catch {
      if connectionGeneration == generation {
        connectionTask = nil
      }
      throw error
    }
  }

  private static func establish(simulator: FBSimulator?) async throws -> FBAXBridgeConnection {
    guard let simulator else {
      throw FBWeakTargetError.simulator
    }
    guard let helperPath = BundledResources.path(forItem: "SimulatorFrameworkBridge") else {
      throw FBAXBridgeError.bridgeUnavailable
    }
    let socketPath = "/tmp/idb_axbridge_\(UUID().uuidString).sock"
    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull()
    let configuration = FBProcessSpawnConfiguration(
      launchPath: helperPath,
      arguments: ["accessibility", "serve", socketPath],
      environment: [:],
      io: io,
      mode: .default
    )
    // Spawn into the booted launchd domain (`.default`) so the guest joins the simulator's mach
    // namespace and can reach app AX servers — the same domain the one-shot describe uses.
    let process = try await simulator.launchProcess(configuration)
    do {
      let fileDescriptor = try await FBAXBridgeConnection.connect(path: socketPath, timeout: 10)
      return FBAXBridgeConnection(fileDescriptor: fileDescriptor, process: process, socketPath: socketPath)
    } catch {
      // Connecting failed, so the `FBAXBridgeConnection` that tears the serve down on deinit was never
      // created — reap the just-spawned serve here so it does not leak as an orphan.
      FBAXBridgeConnection.teardown(fileDescriptor: nil, process: process, socketPath: socketPath)
      throw error
    }
  }
}

// MARK: - Connection

/// A connected Unix-domain socket to a running `accessibility serve` guest, plus the retained guest
/// process handle (retaining it keeps the serve process alive). Frames are 4-byte big-endian length +
/// JSON. Blocking socket I/O runs on a dedicated serial queue so it never blocks a cooperative thread,
/// and the serial queue also guarantees request/response frames never interleave.
///
// SAFETY: the stored properties are immutable and only read; all socket I/O is serialized on the
// private `queue`, which processes one request/response frame pair at a time, so no mutable state is
// shared across threads. Mirrors the `@unchecked Sendable` convention in FBRemoteInvoking.
// patternlint-disable-next-line unchecked-sendable
final class FBAXBridgeConnection: @unchecked Sendable {
  private let fileDescriptor: Int32
  private let process: FBSubprocess<AnyObject, AnyObject, AnyObject>
  private let socketPath: String
  private let queue = DispatchQueue(label: "com.facebook.FBSimulatorControl.axbridge.connection")

  /// Per-`recv` deadline (SO_RCVTIMEO) so a hung or dead guest can't wedge a round-trip forever;
  /// generous relative to a warm read (~20ms), so it only trips on a genuine stall, after which the
  /// round-trip recovery drops and re-establishes the connection.
  private static let roundTripTimeoutSeconds = 30

  init(fileDescriptor: Int32, process: FBSubprocess<AnyObject, AnyObject, AnyObject>, socketPath: String) {
    self.fileDescriptor = fileDescriptor
    self.process = process
    self.socketPath = socketPath
  }

  /// Releases everything a connection attempt can own: the socket, the long-lived serve process, and
  /// the socket file. Shared by `deinit` and the establish-failure path, which owns everything except
  /// the descriptor (`nil`) — so both reap a serve the same way and neither can drift from the other.
  static func teardown(fileDescriptor: Int32?, process: FBSubprocess<AnyObject, AnyObject, AnyObject>, socketPath: String) {
    if let fileDescriptor {
      close(fileDescriptor)
    }
    if process.processIdentifier > 0 {
      kill(process.processIdentifier, SIGKILL)
    }
    unlink(socketPath)
  }

  deinit {
    // Best-effort teardown when the reader holding this connection is released (e.g. the host process
    // exits gracefully).
    Self.teardown(fileDescriptor: fileDescriptor, process: process, socketPath: socketPath)
  }

  func roundTrip(_ requestData: Data) async throws -> Data {
    // Single-resume by construction: the serial queue block resumes the continuation exactly once
    // (success or error) with no timeout/cancellation racing the completion, so a plain checked
    // continuation is safe here (unlike the DTX receipt path, which needs AssertingSafeContinuation
    // to arbitrate a receipt/deadline/cancel three-way race).
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
      queue.async { [fileDescriptor] in
        do {
          try FBAXBridgeConnection.writeFrame(fileDescriptor, requestData)
          let responseData = try FBAXBridgeConnection.readFrame(fileDescriptor)
          continuation.resume(returning: responseData)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Connects to the guest's UDS, retrying until it binds (the guest spawns asynchronously) or the
  /// timeout elapses. Runs on a background queue so the blocking retry never occupies a cooperative
  /// thread.
  static func connect(path: String, timeout: TimeInterval) async throws -> Int32 {
    // Single-resume by construction (the background block resumes once), so a plain checked
    // continuation is safe.
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
      DispatchQueue.global().async {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
          let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
          if fileDescriptor >= 0 {
            if connectSocket(fileDescriptor, toPath: path) {
              var noSigPipe: Int32 = 1
              setsockopt(fileDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
              // Bound each blocking `recv` so a hung/dead guest can't wedge the caller forever; a read
              // that stalls past the deadline fails and the round-trip recovery re-establishes.
              var readTimeout = timeval(tv_sec: roundTripTimeoutSeconds, tv_usec: 0)
              setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &readTimeout, socklen_t(MemoryLayout<timeval>.size))
              continuation.resume(returning: fileDescriptor)
              return
            }
            close(fileDescriptor)
          }
          usleep(100_000)
        } while Date() < deadline
        continuation.resume(throwing: FBAXBridgeError.guestFailure("timed out connecting to the serve socket at \(path)"))
      }
    }
  }

  private static func connectSocket(_ fileDescriptor: Int32, toPath path: String) -> Bool {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    let copied = path.withCString { source -> Bool in
      let length = strlen(source)
      guard length < capacity else { return false }
      withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
          _ = memcpy(destination, source, length + 1)
        }
      }
      return true
    }
    guard copied else { return false }
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    return result == 0
  }

  // MARK: - Framing

  private static func writeFrame(_ fileDescriptor: Int32, _ payload: Data) throws {
    try writeAll(fileDescriptor, encodeLength(payload.count))
    try writeAll(fileDescriptor, payload)
  }

  private static func readFrame(_ fileDescriptor: Int32) throws -> Data {
    let header = try readAll(fileDescriptor, count: 4)
    let length = decodeLength(header)
    // A zero-length frame is never valid: the guest always sends a non-empty JSON envelope
    // ({"ok":...}), so length 0 (or an absurd length) means a desynced/corrupt stream, not empty data.
    // Matches the guest's frame cap: a length outside it means a desynced or corrupt stream, not a
    // huge tree. Keep the two in step — the guest rejects (and never writes) frames above this.
    guard length > 0, length < 16 * 1024 * 1024 else {
      throw FBAXBridgeError.guestFailure("invalid response frame length \(length)")
    }
    return try readAll(fileDescriptor, count: length)
  }

  private static func encodeLength(_ count: Int) -> Data {
    let value = UInt32(count)
    return Data([
      UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff),
    ])
  }

  private static func decodeLength(_ data: Data) -> Int {
    let bytes = [UInt8](data)
    return (Int(bytes[0]) << 24) | (Int(bytes[1]) << 16) | (Int(bytes[2]) << 8) | Int(bytes[3])
  }

  private static func writeAll(_ fileDescriptor: Int32, _ data: Data) throws {
    try data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      var offset = 0
      while offset < raw.count {
        let written = send(fileDescriptor, base + offset, raw.count - offset, 0)
        if written < 0 {
          // A signal interrupted the syscall (we SIGKILL the serve process on teardown) — retry
          // rather than surface a spurious failure on an otherwise-healthy connection.
          if errno == EINTR { continue }
          throw FBAXBridgeError.guestFailure("socket write failed: \(String(cString: strerror(errno)))")
        }
        if written == 0 {
          throw FBAXBridgeError.guestFailure("socket write returned 0")
        }
        offset += written
      }
    }
  }

  private static func readAll(_ fileDescriptor: Int32, count: Int) throws -> Data {
    var buffer = Data(count: count)
    try buffer.withUnsafeMutableBytes { raw in
      guard let base = raw.baseAddress else { return }
      var offset = 0
      while offset < count {
        let got = recv(fileDescriptor, base + offset, count - offset, 0)
        if got < 0 {
          if errno == EINTR { continue } // interrupted by a signal — retry
          if errno == EAGAIN || errno == EWOULDBLOCK {
            // The SO_RCVTIMEO deadline elapsed with no data — the guest is hung or gone. Surface a
            // timeout so the round-trip recovery drops this connection and re-establishes a fresh serve.
            throw FBAXBridgeError.guestFailure("serve read timed out after \(roundTripTimeoutSeconds)s")
          }
          throw FBAXBridgeError.guestFailure("socket read failed: \(String(cString: strerror(errno)))")
        }
        if got == 0 {
          throw FBAXBridgeError.guestFailure("serve socket closed by peer") // EOF: serve process gone
        }
        offset += got
      }
    }
    return buffer
  }
}

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
///   pays the spawn+dlopen cost every read.
/// - `FBAXBridgePersistentTransport` spawns the guest once (`accessibility serve <socket>`) and reads
///   over a reused Unix-domain socket, so warm reads avoid that cost — the path a long-lived host
///   process (companion, `ui shell`, a streaming hit-test server) should use.
///
/// `read` returns the guest's raw JSON response bytes (a `Sendable` `Data`, so it crosses the actor
/// boundary cleanly); the conformer parses the `{ "ok", "tree" | "error" }` envelope.
/// Selects how a frontmost read resolves the foreground app. Raw values are the wire values the guest's
/// `method` request key accepts.
public enum FBAXBridgeFrontmostMethod: String, Sendable, CaseIterable {
  /// Positional: a system-wide accessibility hit-test at the screen-centre anchor (the default).
  case centerPoint = "center-point"
  /// The in-guest window-server frontmost (via AXPTranslator) — the authoritative frontmost app.
  case windowServer = "window-server"
  /// The in-guest RunningBoard foreground process (the app holding the visibility endowment).
  case runningBoard = "runningboard"
}

/// What the element at a write's point must still be for the write to go ahead: one node attribute and
/// the value it has to equal, compared by the guest against whatever it actually hit-tests there.
///
/// The key is an `FBAXWire.Node` rather than a string because only the attributes the tree walk fetches
/// can be asserted on — the assertion is built from a node the host read off this same wire, so a key
/// outside that set could not have come from there, and the guest refuses it as a bad request.
struct FBAXBridgeWriteAssertion: Sendable, Equatable {
  let key: FBAXWire.Node
  let value: String
}

/// One point-addressed write, in the two shapes the transports send it as. Both renderings are
/// declared together so a write means the same thing over either transport.
struct FBAXBridgeWriteRequest: Sendable, Equatable {
  /// Which write, and the one argument that write takes.
  enum Kind: Sendable, Equatable {
    case perform(FBAXWire.Action)
    case setValue(String)
  }

  let kind: Kind
  let x: Double
  let y: Double
  /// The application to hit-test within. `nil` hit-tests display-wide, resolving the owning app in-guest;
  /// the guest rejects a pid that is present and non-positive rather than reading it as "no pid".
  let pid: pid_t?
  let assertion: FBAXBridgeWriteAssertion?

  var verb: FBAXWire.Verb {
    switch kind {
    case .perform: .perform
    case .setValue: .setValue
    }
  }

  /// The one-shot spawn's argv. The guest's front-end reads flags in pairs, so every flag carries a
  /// value and an absent option contributes nothing rather than an empty argument.
  var arguments: [String] {
    var arguments = ["accessibility", verb.rawValue]
    arguments += FBAXWire.Request.x.argument("\(x)")
    arguments += FBAXWire.Request.y.argument("\(y)")
    if let pid {
      arguments += FBAXWire.Request.pid.argument("\(pid)")
    }
    switch kind {
    case let .perform(action):
      arguments += FBAXWire.Request.action.argument(action.rawValue)
    case let .setValue(value):
      arguments += FBAXWire.Request.value.argument(value)
    }
    if let assertion {
      arguments += FBAXWire.Request.assertKey.argument(assertion.key.rawValue)
      arguments += FBAXWire.Request.assertValue.argument(assertion.value)
    }
    return arguments
  }

  /// The persistent transport's JSON request object, carrying the same fields the argv above does.
  var payload: [String: Any] {
    var payload: [String: Any] = [
      FBAXWire.Request.verb.key: verb.rawValue,
      FBAXWire.Request.x.key: x,
      FBAXWire.Request.y.key: y,
    ]
    if let pid {
      payload[FBAXWire.Request.pid.key] = Int(pid)
    }
    switch kind {
    case let .perform(action):
      payload[FBAXWire.Request.action.key] = action.rawValue
    case let .setValue(value):
      payload[FBAXWire.Request.value.key] = value
    }
    if let assertion {
      payload[FBAXWire.Request.assertKey.key] = assertion.key.rawValue
      payload[FBAXWire.Request.assertValue.key] = assertion.value
    }
    return payload
  }
}

protocol FBAXBridgeTransport {
  /// Reads the whole element tree for `pid` (the guest `describe` verb), bounded by the caller's
  /// depth and node budget — the host owns those bounds so both XCUI-grade backends truncate alike.
  ///
  /// `attributes` names what to fetch per element; nil leaves the guest on `Node.defaultFetchList`, so a
  /// default read is byte-identical on the wire to one from a host that did not know the field existed.
  func read(pid: pid_t, maxDepth: Int, maxNodes: Int, attributes: [String]?, explainUnreachable: Bool, traversal: FBAXTraversal, automationMode: Bool?) async throws -> Data
  /// Fused frontmost read (the guest `describe` verb with no pid): the guest resolves the frontmost app
  /// in-guest via `method` (anchored at the given screen point for `.centerPoint`) AND reads its tree in
  /// this one round-trip — no host-side CoreSimulator query and no separate pid call. The response
  /// envelope carries the resolved pid alongside the tree. This is the axbridge frontmost optimization:
  /// one IPC hop.
  func readFrontmost(x: Double, y: Double, maxDepth: Int, maxNodes: Int, method: FBAXBridgeFrontmostMethod, attributes: [String]?, explainUnreachable: Bool, traversal: FBAXTraversal, automationMode: Bool?) async throws -> Data
  /// Reads just the element at a screen point (the guest `hittest` verb with no pid) — a system-wide
  /// hit-test that resolves the element and its owning app in-guest in one round-trip, with no walk and
  /// no separate frontmost pid query. The response carries the owning pid alongside the hit node.
  func hitTest(x: Double, y: Double, attributes: [String]?) async throws -> Data
  /// Sends one point-addressed write (the guest `perform` or `setvalue` verb) and returns its envelope.
  ///
  /// One entry point rather than one per verb: the guest splits them because performing an action and
  /// setting an attribute are different runtime calls, but a transport only ships the request, and the
  /// request already says which it is.
  func write(_ request: FBAXBridgeWriteRequest) async throws -> Data
}

// MARK: - One-shot transport

/// Spawns the guest once per read and returns its stdout JSON.
struct FBAXBridgeOneshotTransport: FBAXBridgeTransport {
  let simulator: FBSimulator

  func read(pid: pid_t, maxDepth: Int, maxNodes: Int, attributes: [String]?, explainUnreachable: Bool, traversal: FBAXTraversal, automationMode: Bool?) async throws -> Data {
    try await spawn(
      ["accessibility", FBAXWire.Verb.describe.rawValue]
        + FBAXWire.Request.pid.argument("\(pid)")
        + FBAXWire.Request.maxDepth.argument("\(maxDepth)")
        + FBAXWire.Request.maxNodes.argument("\(maxNodes)")
        + Self.attributeArgument(attributes)
        + Self.explainArgument(explainUnreachable)
        + Self.traversalArgument(traversal)
        + Self.automationArgument(automationMode)
    )
  }

  func readFrontmost(x: Double, y: Double, maxDepth: Int, maxNodes: Int, method: FBAXBridgeFrontmostMethod, attributes: [String]?, explainUnreachable: Bool, traversal: FBAXTraversal, automationMode: Bool?) async throws -> Data {
    try await spawn(
      ["accessibility", FBAXWire.Verb.describe.rawValue]
        + FBAXWire.Request.x.argument("\(x)")
        + FBAXWire.Request.y.argument("\(y)")
        + FBAXWire.Request.maxDepth.argument("\(maxDepth)")
        + FBAXWire.Request.maxNodes.argument("\(maxNodes)")
        + FBAXWire.Request.method.argument(method.rawValue)
        + Self.attributeArgument(attributes)
        + Self.explainArgument(explainUnreachable)
        + Self.traversalArgument(traversal)
        + Self.automationArgument(automationMode)
    )
  }

  func hitTest(x: Double, y: Double, attributes: [String]?) async throws -> Data {
    try await spawn(
      ["accessibility", FBAXWire.Verb.hitTest.rawValue]
        + FBAXWire.Request.x.argument("\(x)")
        + FBAXWire.Request.y.argument("\(y)")
        + Self.attributeArgument(attributes)
    )
  }

  /// Sent only for a non-default traversal, so a default read's argv stays byte-identical to what a guest
  /// predating the field expects.
  static func traversalArgument(_ traversal: FBAXTraversal) -> [String] {
    switch traversal {
    case .semantic: FBAXWire.Request.translatorVocabulary.argument("1")
    case .singleFetch: FBAXWire.Request.snapshotTree.argument("1")
    case .viewHierarchy: []
    }
  }

  /// Absent unless asked for, so the argv of a read that wants no explanations is unchanged.
  private static func explainArgument(_ explainUnreachable: Bool) -> [String] {
    guard explainUnreachable else {
      return []
    }
    return FBAXWire.Request.explainUnreachable.argument("1")
  }

  /// Absent unless the caller asked, so a read that does not care leaves the device alone and its argv
  /// stays byte-identical to what a guest predating the field expects.
  private static func automationArgument(_ automationMode: Bool?) -> [String] {
    guard let automationMode else {
      return []
    }
    return FBAXWire.Request.automationMode.argument(automationMode ? "1" : "0")
  }

  /// The attribute list as the one-shot front-end takes it: comma-separated, because the guest reads argv
  /// strictly in flag/value pairs and an attribute name never contains a comma. Absent for a default
  /// read, so its argv is unchanged.
  private static func attributeArgument(_ attributes: [String]?) -> [String] {
    guard let attributes, !attributes.isEmpty else {
      return []
    }
    return FBAXWire.Request.attributes.argument(attributes.joined(separator: ","))
  }

  func write(_ request: FBAXBridgeWriteRequest) async throws -> Data {
    try await spawn(request.arguments)
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

  func read(pid: pid_t, maxDepth: Int, maxNodes: Int, attributes: [String]?, explainUnreachable: Bool, traversal: FBAXTraversal, automationMode: Bool?) async throws -> Data {
    try await roundTripWithRecovery(
      Self.adding(
        attributes: attributes,
        explainUnreachable: explainUnreachable,
        traversal: traversal,
        automationMode: automationMode,
        to: [
          FBAXWire.Request.verb.key: FBAXWire.Verb.describe.rawValue,
          FBAXWire.Request.pid.key: Int(pid),
          FBAXWire.Request.maxDepth.key: maxDepth,
          FBAXWire.Request.maxNodes.key: maxNodes,
        ]))
  }

  func readFrontmost(x: Double, y: Double, maxDepth: Int, maxNodes: Int, method: FBAXBridgeFrontmostMethod, attributes: [String]?, explainUnreachable: Bool, traversal: FBAXTraversal, automationMode: Bool?) async throws -> Data {
    try await roundTripWithRecovery(
      Self.adding(
        attributes: attributes,
        explainUnreachable: explainUnreachable,
        traversal: traversal,
        automationMode: automationMode,
        to: [
          FBAXWire.Request.verb.key: FBAXWire.Verb.describe.rawValue,
          FBAXWire.Request.x.key: x,
          FBAXWire.Request.y.key: y,
          FBAXWire.Request.maxDepth.key: maxDepth,
          FBAXWire.Request.maxNodes.key: maxNodes,
          FBAXWire.Request.method.key: method.rawValue,
        ]))
  }

  func hitTest(x: Double, y: Double, attributes: [String]?) async throws -> Data {
    try await roundTripWithRecovery(
      Self.adding(
        attributes: attributes,
        explainUnreachable: false,
        // A hit-test resolves one element positionally; there is no traversal to choose.
        traversal: .viewHierarchy,
        // A hit-test never asserts the mode: it resolves one element, not a tree.
        automationMode: nil,
        to: [
          FBAXWire.Request.verb.key: FBAXWire.Verb.hitTest.rawValue,
          FBAXWire.Request.x.key: x,
          FBAXWire.Request.y.key: y,
        ]))
  }

  /// Adds the attribute list to a request payload, or leaves the payload untouched for a default read —
  /// an absent field is what makes that read's bytes identical to a host that predates the field.
  static func adding(
    attributes: [String]?,
    explainUnreachable: Bool,
    traversal: FBAXTraversal,
    automationMode: Bool?,
    to payload: [String: Any]
  ) -> [String: Any] {
    var payload = payload
    if let attributes, !attributes.isEmpty {
      payload[FBAXWire.Request.attributes.key] = attributes
    }
    if explainUnreachable {
      payload[FBAXWire.Request.explainUnreachable.key] = true
    }
    if traversal == .semantic {
      payload[FBAXWire.Request.translatorVocabulary.key] = true
    }
    if traversal == .singleFetch {
      payload[FBAXWire.Request.snapshotTree.key] = true
    }
    // Present only when the caller asked, so an unset request leaves the device alone rather than
    // asserting a default the caller did not choose.
    if let automationMode {
      payload[FBAXWire.Request.automationMode.key] = automationMode
    }
    return payload
  }

  func write(_ request: FBAXBridgeWriteRequest) async throws -> Data {
    try await roundTripWithoutResend(request.payload)
  }

  /// Sends one request over the reused connection and never re-sends it, for requests that are not safe
  /// to run twice.
  ///
  /// `roundTripWithRecovery` retries a failed round-trip, which is right for a read and wrong for a
  /// write: a round-trip that fails after the request reached the guest — a lost response frame, a
  /// `recv` deadline that elapsed while the application was still running the action — is
  /// indistinguishable from one that failed before it, so retrying risks pressing a button twice. A
  /// failed write is reported instead, and the dead connection is dropped so the caller's next attempt
  /// establishes a fresh serve rather than reusing it.
  private func roundTripWithoutResend(_ request: [String: Any]) async throws -> Data {
    let requestData = try JSONSerialization.data(withJSONObject: request)
    let (connection, generation) = try await self.connection()
    do {
      return try await connection.roundTrip(requestData)
    } catch {
      // Compare-and-clear on the generation that failed, for the reason `roundTripWithRecovery` gives:
      // a concurrent caller may already have replaced this connection with a healthy one.
      if connectionGeneration == generation {
        connectionTask = nil
      }
      throw error
    }
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
    let socketPath = FBAXBridgeSocket.path(forConnection: UUID().uuidString)
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
      return FBAXBridgeConnection(
        fileDescriptor: fileDescriptor,
        process: process,
        socketPath: socketPath,
        logger: simulator.logger
      )
    } catch {
      // Connecting failed, so the `FBAXBridgeConnection` that tears the serve down on deinit was never
      // created — reap the just-spawned serve here so it does not leak as an orphan.
      FBAXBridgeConnection.teardown(
        fileDescriptor: nil,
        processIdentifier: process.processIdentifier,
        socketPath: socketPath,
        logger: simulator.logger
      )
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
  private let logger: (any FBControlCoreLogger)?
  private let queue = DispatchQueue(label: "com.facebook.FBSimulatorControl.axbridge.connection")

  /// Per-`recv` deadline (SO_RCVTIMEO), so a hung or dead guest cannot wedge a round trip forever.
  ///
  /// This bounds silence, not total read time: `readAll` loops `recv` and each call gets the full
  /// deadline, so every chunk that arrives resets it. Only a guest that says nothing at all for the
  /// deadline trips it, after which the recovery path drops and re-establishes the connection.
  /// Deliberately not derived from read cost, which varies by orders of magnitude across applications.
  private static let receiveTimeoutSeconds = 30

  init(
    fileDescriptor: Int32,
    process: FBSubprocess<AnyObject, AnyObject, AnyObject>,
    socketPath: String,
    logger: (any FBControlCoreLogger)?
  ) {
    self.fileDescriptor = fileDescriptor
    self.process = process
    self.socketPath = socketPath
    self.logger = logger
  }

  /// Releases everything a connection attempt can own: the socket, the long-lived serve process, and
  /// the socket file. Shared by `deinit` and the establish-failure path, which owns everything except
  /// the descriptor (`nil`) — so both reap a serve the same way and neither can drift from the other.
  ///
  /// Takes the pid rather than the process because that is all it needs, which also lets a test drive
  /// it against a throwaway child instead of a spawned guest.
  static func teardown(
    fileDescriptor: Int32?,
    processIdentifier: pid_t,
    socketPath: String,
    logger: (any FBControlCoreLogger)?
  ) {
    if let fileDescriptor {
      close(fileDescriptor)
    }
    if processIdentifier > 0 {
      // Logged before the kill so the exit reporter's "exited with signal 9" reads as expected
      // teardown, not a crash.
      logger?.log("Releasing axbridge connection: terminating guest serve process \(processIdentifier) with SIGKILL, this exit is expected")
      kill(processIdentifier, SIGKILL)
    }
    unlink(socketPath)
  }

  deinit {
    // Best-effort teardown when the memoized transport holding this connection is released — which,
    // because the transport lives in the target's `commandCache`, means the target went away or the
    // host process exited gracefully. Dropping a reader does not reach here.
    Self.teardown(
      fileDescriptor: fileDescriptor,
      processIdentifier: process.processIdentifier,
      socketPath: socketPath,
      logger: logger
    )
  }

  func roundTrip(_ requestData: Data) async throws -> Data {
    // Single-resume by construction: the serial queue block resumes the continuation exactly once
    // (success or error) with no timeout/cancellation racing the completion, so a plain checked
    // continuation is safe here (unlike the DTX receipt path, which needs AssertingSafeContinuation
    // to arbitrate a receipt/deadline/cancel three-way race).
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
      queue.async { [fileDescriptor, process] in
        do {
          try FBAXBridgeConnection.writeFrame(fileDescriptor, requestData)
          let responseData = try FBAXBridgeConnection.readFrame(fileDescriptor, guest: process)
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
              // SO_RCVTIMEO — see receiveTimeoutSeconds.
              var readTimeout = timeval(tv_sec: receiveTimeoutSeconds, tv_usec: 0)
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

  static func writeFrame(_ fileDescriptor: Int32, _ payload: Data) throws {
    try writeAll(fileDescriptor, encodeLength(payload.count))
    try writeAll(fileDescriptor, payload)
  }

  static func readFrame(
    _ fileDescriptor: Int32,
    guest: FBSubprocess<AnyObject, AnyObject, AnyObject>?
  ) throws -> Data {
    let header = try readAll(fileDescriptor, count: 4, guest: guest)
    let length = decodeLength(header)
    // The guest always sends a non-empty JSON envelope and never writes frames above this cap (keep
    // the two in step), so a length outside the range means a desynced or corrupt stream.
    guard length > 0, length < 16 * 1024 * 1024 else {
      throw FBAXBridgeError.guestFailure("invalid response frame length \(length)")
    }
    return try readAll(fileDescriptor, count: length, guest: guest)
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

  /// What a caller is told when the guest's socket reaches EOF: a reader that was killed, exited
  /// cleanly, or crashed are three different problems, and "closed by peer" distinguishes none of
  /// them — so the guest subprocess's exit status is folded into the message. An unresolved exit
  /// future contributes nothing; the message then reports that no exit status was recorded.
  static func socketClosedMessage(process: FBSubprocess<AnyObject, AnyObject, AnyObject>?) -> String {
    guard let process else {
      return socketClosedMessage(pid: nil, signal: nil, exitCode: nil)
    }
    // `hasCompleted` first — never block the read path to report why the read failed.
    return socketClosedMessage(
      pid: process.processIdentifier,
      signal: process.signal.hasCompleted ? process.signal.result?.intValue : nil,
      exitCode: process.exitCode.hasCompleted ? process.exitCode.result?.intValue : nil
    )
  }

  /// The message itself, over the values rather than the process that carries them.
  ///
  /// Split out so the wording is coverable without constructing a subprocess: the part worth testing is
  /// which of three answers a caller gets, and that does not need a real process to exercise.
  static func socketClosedMessage(pid: pid_t?, signal: Int?, exitCode: Int?) -> String {
    let base = "serve socket closed by peer"
    guard let pid else {
      return base
    }
    // A signalled exit takes precedence and is the more actionable of the two: it means something outside
    // the reader ended it — the system reclaiming memory, or a stray kill — rather than the reader
    // deciding to stop.
    if let signal, signal != 0 {
      return "\(base): the guest (pid \(pid)) was killed by signal \(signal)"
    }
    if let exitCode {
      return "\(base): the guest (pid \(pid)) exited with code \(exitCode)"
    }
    return "\(base): the guest (pid \(pid)) is gone, with no exit status recorded"
  }

  private static func readAll(
    _ fileDescriptor: Int32,
    count: Int,
    guest: FBSubprocess<AnyObject, AnyObject, AnyObject>?
  ) throws -> Data {
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
            throw FBAXBridgeError.guestFailure("serve read timed out after \(receiveTimeoutSeconds)s with no data")
          }
          throw FBAXBridgeError.guestFailure("socket read failed: \(String(cString: strerror(errno)))")
        }
        if got == 0 {
          // EOF: the serve process is gone. Detected promptly — this is not the 30s timeout above — but
          // the message says only that it went away, not why.
          throw FBAXBridgeError.guestFailure(FBAXBridgeConnection.socketClosedMessage(process: guest))
        }
        offset += got
      }
    }
    return buffer
  }
}

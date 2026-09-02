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
/// - `FBAXBridgePersistentTransport` reads over an `accessibility serve <socket>` guest that outlives
///   the read, so warm reads avoid that cost. It may spawn the guest or adopt one already running.
///   Whether it keeps the connection between reads depends on who owns the guest: a private one is
///   held, the shared one is released so the next process can have it.
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

struct FBAXBridgeReadRequest: Sendable, Equatable {
  let maxDepth: Int
  let maxNodes: Int
  let attributes: [String]?
  let explainUnreachable: Bool
  let traversal: FBAXTraversal
  let automationMode: Bool?

  func appendingArguments(to arguments: [String]) -> [String] {
    var arguments = arguments
    arguments += FBAXWire.Request.maxDepth.argument("\(maxDepth)")
    arguments += FBAXWire.Request.maxNodes.argument("\(maxNodes)")
    if let attributes, !attributes.isEmpty {
      arguments += FBAXWire.Request.attributes.argument(attributes.joined(separator: ","))
    }
    if explainUnreachable {
      arguments += FBAXWire.Request.explainUnreachable.argument("1")
    }
    switch traversal {
    case .semantic:
      arguments += FBAXWire.Request.translatorVocabulary.argument("1")
    case .singleFetch:
      arguments += FBAXWire.Request.snapshotTree.argument("1")
    case .viewHierarchy:
      break
    }
    if let automationMode {
      arguments += FBAXWire.Request.automationMode.argument(automationMode ? "1" : "0")
    }
    return arguments
  }

  func appendingPayload(to payload: [String: Any]) -> [String: Any] {
    var payload = payload
    payload[FBAXWire.Request.maxDepth.key] = maxDepth
    payload[FBAXWire.Request.maxNodes.key] = maxNodes
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
    if let automationMode {
      payload[FBAXWire.Request.automationMode.key] = automationMode
    }
    return payload
  }
}

enum FBAXBridgeRequest: Sendable {
  case read(pid: pid_t, options: FBAXBridgeReadRequest)
  case readFrontmost(x: Double, y: Double, method: FBAXBridgeFrontmostMethod, options: FBAXBridgeReadRequest)
  case hitTest(x: Double, y: Double, attributes: [String]?)
  case write(FBAXBridgeWriteRequest)
  case ping

  var mayRetry: Bool {
    if case .write = self {
      return false
    }
    return true
  }

  var arguments: [String] {
    switch self {
    case let .read(pid, options):
      return options.appendingArguments(
        to: ["accessibility", FBAXWire.Verb.describe.rawValue]
          + FBAXWire.Request.pid.argument("\(pid)"))
    case let .readFrontmost(x, y, method, options):
      return options.appendingArguments(
        to: ["accessibility", FBAXWire.Verb.describe.rawValue]
          + FBAXWire.Request.x.argument("\(x)")
          + FBAXWire.Request.y.argument("\(y)")
          + FBAXWire.Request.method.argument(method.rawValue))
    case let .hitTest(x, y, attributes):
      var arguments =
        ["accessibility", FBAXWire.Verb.hitTest.rawValue]
        + FBAXWire.Request.x.argument("\(x)")
        + FBAXWire.Request.y.argument("\(y)")
      if let attributes, !attributes.isEmpty {
        arguments += FBAXWire.Request.attributes.argument(attributes.joined(separator: ","))
      }
      return arguments
    case let .write(request):
      return request.arguments
    case .ping:
      return ["accessibility", "ping"]
    }
  }

  var payload: [String: Any] {
    switch self {
    case let .read(pid, options):
      return options.appendingPayload(to: [
        FBAXWire.Request.verb.key: FBAXWire.Verb.describe.rawValue,
        FBAXWire.Request.pid.key: Int(pid),
      ])
    case let .readFrontmost(x, y, method, options):
      return options.appendingPayload(to: [
        FBAXWire.Request.verb.key: FBAXWire.Verb.describe.rawValue,
        FBAXWire.Request.x.key: x,
        FBAXWire.Request.y.key: y,
        FBAXWire.Request.method.key: method.rawValue,
      ])
    case let .hitTest(x, y, attributes):
      var payload: [String: Any] = [
        FBAXWire.Request.verb.key: FBAXWire.Verb.hitTest.rawValue,
        FBAXWire.Request.x.key: x,
        FBAXWire.Request.y.key: y,
      ]
      if let attributes, !attributes.isEmpty {
        payload[FBAXWire.Request.attributes.key] = attributes
      }
      return payload
    case let .write(request):
      return request.payload
    case .ping:
      return [FBAXWire.Request.verb.key: "ping"]
    }
  }
}

protocol FBAXBridgeTransport {
  func send(_ request: FBAXBridgeRequest) async throws -> Data
}

// MARK: - One-shot transport

/// Spawns the guest once per read and returns its stdout JSON.
struct FBAXBridgeOneshotTransport: FBAXBridgeTransport {
  let simulator: FBSimulator

  func send(_ request: FBAXBridgeRequest) async throws -> Data {
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

/// Reads over an `accessibility serve <socket>` guest rather than spawning one per read. An actor so
/// concurrent callers do not each establish their own connection, and reads are serialized (the guest
/// handles one request at a time). Memoized per simulator and per persistence, so a long-lived host
/// process amortizes the spawn and warmup across every read, and a shared reader is never handed the
/// private transport.
actor FBAXBridgePersistentTransport: FBAXBridgeTransport {
  private weak var simulator: FBSimulator?
  /// Which kind of bridge this transport reaches: whether it may discover one on the simulator's
  /// well-known socket, and whether a guest it spawns exits when its client goes. Whether a connection
  /// is kept between round trips is decided by the guest that was established, not by this. Framing a
  /// request is identical either way.
  private let persistence: FBAXBridgePersistence
  private var connectionTask: Task<FBAXBridgeConnection, Error>?

  init(simulator: FBSimulator, persistence: FBAXBridgePersistence) {
    self.simulator = simulator
    self.persistence = persistence
  }

  func send(_ request: FBAXBridgeRequest) async throws -> Data {
    if request.mayRetry {
      return try await roundTripWithRecovery(request.payload)
    }
    return try await roundTripWithoutResend(request.payload)
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
    let connection = try await self.connection()
    do {
      let response = try await connection.roundTrip(requestData)
      releaseConnectionIfNotRetained(connection)
      return response
    } catch {
      connectionTask = nil
      throw error
    }
  }

  /// Sends one request over the reused connection, recovering from a terminated serve process.
  private func roundTripWithRecovery(_ request: [String: Any]) async throws -> Data {
    let requestData = try JSONSerialization.data(withJSONObject: request)
    do {
      let connection = try await self.connection()
      do {
        let response = try await connection.roundTrip(requestData)
        releaseConnectionIfNotRetained(connection)
        return response
      } catch {
        connectionTask = nil
        throw error
      }
    } catch {
      // The connection is likely dead — the serve process terminated (crash, sim teardown, external
      // kill), or the stream desynced after a partial frame. It has been dropped above; re-establish and
      // retry the request once, so recovery is invisible to the caller. A second failure — the
      // application's accessibility server genuinely being down — is surfaced.
      let connection = try await self.connection()
      do {
        let response = try await connection.roundTrip(requestData)
        releaseConnectionIfNotRetained(connection)
        return response
      } catch {
        connectionTask = nil
        throw error
      }
    }
  }

  /// Drops the memoized connection unless the guest it reaches is private to this host.
  ///
  /// A shared bridge is released the moment the work that needed it is done, because the guest serves
  /// one client at a time: holding the connection between reads would keep its only slot and make every
  /// other process on the machine wait. The guest stays up either way, so the next read re-adopts it
  /// rather than paying for a spawn.
  ///
  /// Keyed on the guest that was established rather than the persistence that was asked for, because a
  /// shared read that finds the bridge busy falls back to a private guest, which is safe to hold.
  private func releaseConnectionIfNotRetained(_ connection: FBAXBridgeConnection) {
    guard !connection.mayBeHeldBetweenRoundTrips else {
      return
    }
    connectionTask = nil
  }

  /// The connection to this transport's guest, established once under concurrent callers.
  ///
  /// Any failure clears the memo. Two callers can therefore race to establish, and the loser re-adopts
  /// over the well-known socket — or spawns, if the shared guest is busy by then.
  private func connection() async throws -> FBAXBridgeConnection {
    if let connectionTask {
      return try await connectionTask.value
    }
    let simulator = self.simulator
    let persistence = self.persistence
    let task = Task { try await Self.establish(simulator: simulator, persistence: persistence) }
    connectionTask = task
    do {
      return try await task.value
    } catch {
      connectionTask = nil
      throw error
    }
  }

  /// How long a guest this transport spawned may sit without traffic before ending itself.
  ///
  /// The guest's historical default rather than a chosen number: nobody has measured how long real
  /// sessions go between reads. For a shared guest it is the only thing that ends one: no host ends it,
  /// and its connection is released after every round trip.
  static let idleTimeoutSeconds = 300

  /// The guest's argv for a spawn.
  ///
  /// The timeout is stated rather than left to the guest's default, because the two ship separately: the
  /// guest lives in the companion's `Resources/` and a consumer may pin an older artifact. A guest
  /// predating the flag ignores it, so this is safe to send to any of them.
  static func serveArguments(
    socketPath: String,
    persistence: FBAXBridgePersistence,
    idleTimeoutSeconds: Int = idleTimeoutSeconds
  ) -> [String] {
    var arguments = ["accessibility", "serve", socketPath, "--idle-timeout", "\(idleTimeoutSeconds)"]
    if persistence == .exclusive {
      // Nobody else can reach an exclusive socket, so once our client goes there is no next one to wait
      // for. Without this the guest would sit through its whole idle window after the host that owned
      // it died, which is the orphan the private socket was supposed to make impossible.
      arguments += ["--exit-on-disconnect", "1"]
    }
    return arguments
  }

  /// How long a running bridge gets to answer before we decide somebody else is holding it.
  ///
  /// A free guest answers in tens of microseconds; one part-way through another shared reader's request
  /// is free again within about thirty milliseconds. Long enough to wait that reader out, short enough
  /// that a bridge held for longer than one turn will not come free soon enough to wait for.
  static let adoptionTimeout: TimeInterval = 0.25

  private enum RunningBridge {
    /// Connected and answered, so nothing else holds it.
    case adopted(Int32)
    /// Nothing is listening: no socket file, or one left behind by a guest that has gone.
    case absent
    /// Listening, but silent — another host is inside its accept loop.
    case busy
  }

  private static func establish(
    simulator: FBSimulator?,
    persistence: FBAXBridgePersistence
  ) async throws -> FBAXBridgeConnection {
    guard let simulator else {
      throw FBWeakTargetError.simulator
    }
    guard let helperPath = BundledResources.path(forItem: "SimulatorFrameworkBridge") else {
      throw FBAXBridgeError.bridgeUnavailable
    }
    // The guest binds into this directory and `bind` will not create it.
    try FBAXBridgeSocket.prepareDirectory()

    // An exclusive bridge is never discovered: its socket name is a UUID only this host knows, so the
    // discovery below applies to the shared case alone.
    guard persistence != .exclusive else {
      let privatePath = FBAXBridgeSocket.path(forConnection: UUID().uuidString)
      return try await spawn(
        simulator: simulator, helperPath: helperPath, socketPath: privatePath,
        persistence: .exclusive, ownership: { .privateToThisHost($0) })
    }

    let sharedPath = FBAXBridgeSocket.path(forSimulator: simulator.udid)
    switch await runningBridge(at: sharedPath) {
    case let .adopted(fileDescriptor):
      simulator.logger.log("Adopted the axbridge guest already serving on \(sharedPath)")
      return FBAXBridgeConnection(fileDescriptor: fileDescriptor, ownership: .shared(nil))
    case .absent:
      return try await spawn(
        simulator: simulator, helperPath: helperPath, socketPath: sharedPath,
        persistence: .shared, ownership: { .shared($0) })
    case .busy:
      // The shared guest will not take a second client until the first leaves, which may be their whole
      // session, so a contended read starts a private guest rather than waiting.
      let privatePath = FBAXBridgeSocket.path(forConnection: UUID().uuidString)
      simulator.logger.log(
        "The axbridge guest on \(sharedPath) is serving another client; starting a private one on \(privatePath)")
      return try await spawn(
        simulator: simulator, helperPath: helperPath, socketPath: privatePath,
        persistence: .exclusive, ownership: { .privateToThisHost($0) })
    }
  }

  /// Whether a bridge is already serving at `path`, and a connection to it if so.
  ///
  /// A busy guest still completes our `connect`, because its address is bound and the accept queue has
  /// room; it just never serves us. Sending something and waiting for a reply is the only way to tell.
  private static func runningBridge(at path: String) async -> RunningBridge {
    guard FileManager.default.fileExists(atPath: path) else {
      return .absent
    }
    let fileDescriptor: Int32
    do {
      fileDescriptor = try await FBAXBridgeConnection.connect(path: path, timeout: adoptionTimeout)
    } catch {
      // The file is there and nothing answers on it: a guest that has gone, leaving its socket behind.
      return .absent
    }
    // The framing calls below block, so they run off the cooperative pool.
    return await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: probe(fileDescriptor: fileDescriptor))
      }
    }
  }

  /// An all-zero `timeval` means "no deadline" to the kernel, not "expire immediately".
  static func receiveWindow(_ timeout: TimeInterval) -> timeval {
    let whole = timeout.rounded(.down)
    return timeval(tv_sec: Int(whole), tv_usec: Int32((timeout - whole) * 1_000_000))
  }

  private static func probe(fileDescriptor: Int32) -> RunningBridge {
    var window = receiveWindow(adoptionTimeout)
    setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &window, socklen_t(MemoryLayout<timeval>.size))
    do {
      let request = try JSONSerialization.data(withJSONObject: FBAXBridgeRequest.ping.payload)
      try FBAXBridgeConnection.writeFrame(fileDescriptor, request)
      _ = try FBAXBridgeConnection.readFrame(fileDescriptor, guest: nil)
    } catch {
      close(fileDescriptor)
      return .busy
    }
    // Back to the working deadline now the probe is done, so a real read gets the full window.
    var readTimeout = timeval(tv_sec: FBAXBridgeConnection.receiveTimeoutSeconds, tv_usec: 0)
    setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &readTimeout, socklen_t(MemoryLayout<timeval>.size))
    return .adopted(fileDescriptor)
  }

  private static func spawn(
    simulator: FBSimulator,
    helperPath: String,
    socketPath: String,
    persistence: FBAXBridgePersistence,
    ownership: (FBSubprocess<AnyObject, AnyObject, AnyObject>) -> FBAXBridgeGuestOwnership
  ) async throws -> FBAXBridgeConnection {
    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull()
    let configuration = FBProcessSpawnConfiguration(
      launchPath: helperPath,
      arguments: serveArguments(socketPath: socketPath, persistence: persistence),
      environment: [:],
      io: io,
      mode: .default
    )
    // Spawn into the booted launchd domain (`.default`) so the guest joins the simulator's mach
    // namespace and can reach app AX servers — the same domain the one-shot describe uses.
    let process = try await simulator.launchProcess(configuration)
    do {
      let fileDescriptor = try await FBAXBridgeConnection.connect(path: socketPath, timeout: 10)
      return FBAXBridgeConnection(fileDescriptor: fileDescriptor, ownership: ownership(process))
    } catch {
      // Nothing to signal. A guest we could not connect to has most likely already exited, and one that
      // is up but unreachable is collected by its own idle timeout — on a socket no other process can
      // discover, so nothing else is waiting on it.
      simulator.logger.log(
        "Could not reach the axbridge guest just spawned on \(socketPath); leaving it to time out")
      throw error
    }
  }
}

// MARK: - Connection

/// A connection's relationship to the guest on the other end, which is what decides whether the
/// connection may be held between round trips.
///
/// An enum rather than an optional handle plus a flag, which would allow states that cannot occur: a
/// guest only we can reach is always one we started, and a shared guest is one anyone may adopt whether
/// we started it or found it.
enum FBAXBridgeGuestOwnership {
  /// Started by us, on a socket whose name only we know. Nobody else can find it, so nobody else can be
  /// waiting for it, and we may keep it for as long as we like.
  case privateToThisHost(FBSubprocess<AnyObject, AnyObject, AnyObject>)
  /// Serving the simulator on its well-known socket. Left running when we go, for the next process that
  /// wants a bridge. The handle is present when we started it and absent when we adopted it — it is kept
  /// only to report why the guest went away if the socket closes under a read.
  case shared(FBSubprocess<AnyObject, AnyObject, AnyObject>?)

  /// The guest process, when there is a handle for it. Diagnostics only.
  var process: FBSubprocess<AnyObject, AnyObject, AnyObject>? {
    switch self {
    case let .privateToThisHost(process): process
    case let .shared(process): process
    }
  }

  /// Whether the guest is private to this host.
  ///
  /// No other process can discover a private guest, so its single client slot may be held between round
  /// trips. The shared one is the opposite: the next reader may be another process entirely, so it is
  /// released as soon as the work is done.
  var isPrivate: Bool {
    switch self {
    case .privateToThisHost: true
    case .shared: false
    }
  }
}

/// A connected Unix-domain socket to a running `accessibility serve` guest. Frames are 4-byte
/// big-endian length + JSON. Blocking socket I/O runs on a dedicated serial queue so it never blocks a
/// cooperative thread, and the serial queue also guarantees request/response frames never interleave.
///
// SAFETY: the stored properties are immutable and only read; all socket I/O is serialized on the
// private `queue`, which processes one request/response frame pair at a time, so no mutable state is
// shared across threads.
// patternlint-disable-next-line unchecked-sendable
final class FBAXBridgeConnection: @unchecked Sendable {
  private let fileDescriptor: Int32
  /// The guest on the other end: its process handle, so a failed read can say why it went away, and
  /// whether it is private to this host, which decides if this connection may be held between reads.
  private let ownership: FBAXBridgeGuestOwnership
  private let queue = DispatchQueue(label: "com.facebook.FBSimulatorControl.axbridge.connection")

  /// Per-`recv` deadline (SO_RCVTIMEO), so a hung or dead guest cannot wedge a round trip forever.
  ///
  /// This bounds silence, not total read time: `readAll` loops `recv` and each call gets the full
  /// deadline, so every chunk that arrives resets it. Only a guest that says nothing at all for the
  /// deadline trips it, after which the recovery path drops and re-establishes the connection.
  /// Deliberately not derived from read cost, which varies by orders of magnitude across applications.
  static let receiveTimeoutSeconds = 30

  /// How many bytes of path a Unix-domain socket address can hold, terminator included. Read from the
  /// struct rather than written down, so it tracks the platform.
  static let sunPathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)

  /// Whether this connection may be kept open between round trips, which is true exactly when the guest
  /// on the other end is private to this host. A shared guest serves one client at a time, so holding it
  /// would make every other process on the machine wait; a private one they cannot reach.
  var mayBeHeldBetweenRoundTrips: Bool {
    ownership.isPrivate
  }

  init(fileDescriptor: Int32, ownership: FBAXBridgeGuestOwnership) {
    self.fileDescriptor = fileDescriptor
    self.ownership = ownership
  }

  deinit {
    // Closing the descriptor is all the teardown there is. A private guest was spawned with
    // `--exit-on-disconnect`, so this is what ends it; a shared one keeps running with its socket
    // intact and ends itself after its idle timeout.
    close(fileDescriptor)
  }

  func roundTrip(_ requestData: Data) async throws -> Data {
    // Single-resume by construction: the serial queue block resumes the continuation exactly once
    // (success or error) with no timeout/cancellation racing the completion, so a plain checked
    // continuation is safe here (unlike the DTX receipt path, which needs AssertingSafeContinuation
    // to arbitrate a receipt/deadline/cancel three-way race).
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
      queue.async { [fileDescriptor, guest = ownership.process] in
        do {
          try FBAXBridgeConnection.writeFrame(fileDescriptor, requestData)
          let responseData = try FBAXBridgeConnection.readFrame(fileDescriptor, guest: guest)
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
    // `connectSocket` refuses an over-long path without reaching the syscall, so the retry loop below
    // would spend the whole deadline and then report a timeout. Checked rather than left to the caller's
    // arithmetic: `bind` truncates such a path and reports success, so nothing downstream catches it.
    guard path.utf8.count < sunPathCapacity else {
      throw FBAXBridgeError.socketPathTooLong(path: path, limit: sunPathCapacity)
    }
    // Single-resume by construction (the background block resumes once), so a plain checked
    // continuation is safe.
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
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

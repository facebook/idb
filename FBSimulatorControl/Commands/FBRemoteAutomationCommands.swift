/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

/// The environment key under which the guest `testmanagerd` publishes its remote-automation socket.
let remoteAutomationSockEnvKey = "TESTMANAGERD_REMOTE_AUTOMATION_SIM_SOCK"

/// Drives UI automation over the guest `testmanagerd` remote-automation channel, without an
/// `.xctest` bundle, runner, or build.
///
/// Reached through `FBSimulator.remoteAutomation()`, which memoizes one instance per target. The
/// underlying `FBRemoteAutomationSession` — socket connect, framework preload, handshake — is built
/// and primed once on first use and reused; a failed build clears the memo so a later call retries.
/// An actor so the memoized session is established exactly once under concurrent callers, without a
/// lock across suspension points.
public actor FBSimulatorRemoteAutomation {

  private weak var simulator: FBSimulator?
  private var sessionTask: Task<FBRemoteAutomationSession, Error>?

  init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  public static func commands(with target: FBSimulator) -> FBSimulatorRemoteAutomation {
    FBSimulatorRemoteAutomation(simulator: target)
  }

  /// Submits a synthesized input event (tap, swipe, …) over the remote-automation channel.
  public func sendHIDEvent(_ event: FBSimulatorHIDEvent) async throws {
    let session = try await self.session()
    let record = try Self.eventRecord(for: event)
    try await session.synthesizeEvent(record)
  }

  /// Reads the accessibility element at a screen point (in points) over the remote-automation
  /// channel and serializes it to the accessibility schema as canonical sorted-keys JSON, matching
  /// the legacy `accessibilityDescribe` point output.
  public func describe(atX x: Double, y: Double, keys: Set<FBAXKeys>) async throws -> Data {
    let session = try await self.session()
    let element = try await Self.describeElement(atX: x, y: y, using: session, keys: keys)
    let response = FBAccessibilityElementsResponse(
      elements: element, profilingData: nil, frameCoverage: nil, additionalFrameCoverage: nil
    )
    return try JSONSerialization.data(withJSONObject: response.asDictionary(), options: .sortedKeys)
  }

  /// Reads the first element in the frontmost app tree whose `key` value equals `markerValue` and
  /// serializes it to the single-element accessibility schema, matching `describe(atX:y:keys:)` for a
  /// point. `(x, y)` is the point probed to discover the frontmost app's pid. `key` must be among the
  /// requested `keys` for the match to be found.
  public func describe(markerValue: String, key: FBAXSearchableKey, keys: Set<FBAXKeys>, anchorX x: Double, anchorY y: Double) async throws -> Data {
    let tree = try await readFrontmostTree(anchorX: x, y: y)
    let elements = Self.describeAllElements(fromTree: tree.root, keys: keys, nestedFormat: false, pid: tree.pid)
    guard let match = Self.matchingElement(inElements: elements, markerValue: markerValue, key: key) else {
      throw FBControlCoreError.describe("Remote automation found no element matching \(key.rawValue)=\"\(markerValue)\"").build()
    }
    let response = FBAccessibilityElementsResponse(
      elements: match, profilingData: nil, frameCoverage: nil, additionalFrameCoverage: nil
    )
    return try JSONSerialization.data(withJSONObject: response.asDictionary(), options: .sortedKeys)
  }

  /// Reads the whole element tree of the frontmost application over the remote-automation channel and
  /// serializes it to the accessibility schema as canonical sorted-keys JSON. `(x, y)` is the point
  /// probed to discover the frontmost app's pid. If the walk hits the depth or node-count bound the
  /// returned tree is incomplete; that is logged rather than passed off as a full tree.
  public func describeAll(anchorX x: Double, y: Double, keys: Set<FBAXKeys>, nestedFormat: Bool) async throws -> Data {
    let tree = try await readFrontmostTree(anchorX: x, y: y)
    let elements = Self.describeAllElements(fromTree: tree.root, keys: keys, nestedFormat: nestedFormat, pid: tree.pid)
    let response = FBAccessibilityElementsResponse(
      elements: .array(elements), profilingData: nil, frameCoverage: nil, additionalFrameCoverage: nil
    )
    return try JSONSerialization.data(withJSONObject: response.asDictionary(), options: .sortedKeys)
  }

  /// Finds the element in the frontmost app tree whose `key` value equals `markerValue` and taps its
  /// frame centre over the remote-automation channel. `(x, y)` is the point probed to discover the
  /// frontmost app's pid.
  public func tap(markerValue: String, key: FBAXSearchableKey, anchorX x: Double, anchorY y: Double) async throws {
    let tree = try await readFrontmostTree(anchorX: x, y: y)
    let elements = Self.describeAllElements(fromTree: tree.root, keys: FBAXKeys.defaultSet, nestedFormat: false, pid: tree.pid)
    guard let center = Self.frameCenter(inElements: elements, markerValue: markerValue, key: key) else {
      throw FBControlCoreError.describe("Remote automation found no element matching \(key.rawValue)=\"\(markerValue)\"").build()
    }
    let session = try await self.session()
    let record = try Self.eventRecord(for: .tapAt(x: center.x, y: center.y))
    try await session.synthesizeEvent(record)
  }

  /// Polls the frontmost app tree over the remote-automation channel until an element whose `key`
  /// value equals `markerValue` appears, or throws when `timeout` elapses. `(x, y)` is the point
  /// probed to discover the frontmost app's pid.
  public func wait(markerValue: String, key: FBAXSearchableKey, timeout: TimeInterval, pollInterval: TimeInterval, anchorX x: Double, anchorY y: Double) async throws {
    let session = try await self.session()
    let found = try await Self.pollUntilFound(
      timeout: timeout,
      pollInterval: pollInterval,
      clock: { Date().timeIntervalSinceReferenceDate },
      sleep: { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) { () -> Bool? in
      // A poll reads the tree directly (rather than via `readFrontmostTree`) so a missing tree retries
      // instead of throwing, and the truncation warning is not logged on every poll iteration.
      let tree = try await session.applicationElementTree(
        anchorX: x, y: y,
        attributes: FBRemoteAutomationAXAttribute.fetchList,
        childrenAttribute: FBRemoteAutomationAXAttribute.children,
        maxDepth: Self.describeMaxDepth,
        maxNodes: Self.describeMaxNodes
      )
      guard let root = tree.root as? [String: Any] else { return nil }
      let elements = Self.describeAllElements(fromTree: root, keys: FBAXKeys.defaultSet, nestedFormat: false, pid: tree.processIdentifier)
      return Self.frameCenter(inElements: elements, markerValue: markerValue, key: key) != nil ? true : nil
    }
    if found == nil {
      throw FBControlCoreError.describe("Remote automation timed out after \(timeout)s waiting for \(key.rawValue)=\"\(markerValue)\". \(Self.accessibilityHint)").build()
    }
  }

  /// Sets `value` on the element at a screen point (in points) over the remote-automation channel.
  public func setValue(_ value: String, atX x: Double, y: Double) async throws {
    let session = try await self.session()
    try await session.setValue(value, atX: x, y: y, valueAttribute: FBRemoteAutomationAXAttribute.value)
  }

  /// Sets `value` on the first element in the frontmost app tree whose `key` value equals
  /// `markerValue`, over the remote-automation channel. `(x, y)` is the point probed to discover the
  /// frontmost app's pid.
  public func setValue(_ value: String, markerValue: String, key: FBAXSearchableKey, anchorX x: Double, anchorY y: Double) async throws {
    let tree = try await readFrontmostTree(anchorX: x, y: y)
    let elements = Self.describeAllElements(fromTree: tree.root, keys: FBAXKeys.defaultSet, nestedFormat: false, pid: tree.pid)
    guard let center = Self.frameCenter(inElements: elements, markerValue: markerValue, key: key) else {
      throw FBControlCoreError.describe("Remote automation found no element matching \(key.rawValue)=\"\(markerValue)\"").build()
    }
    let session = try await self.session()
    try await session.setValue(value, atX: center.x, y: center.y, valueAttribute: FBRemoteAutomationAXAttribute.value)
  }

  // MARK: - Reads

  private static let describeMaxDepth = 50
  private static let describeMaxNodes = 3000

  /// Appended to read-failure errors. An empty tree/element almost always means the target app's
  /// in-process accessibility server never started — that requires `ApplicationAccessibilityEnabled`
  /// (`com.apple.Accessibility`) to have been set *before* the app launched. The flag is consumed at
  /// launch (a live read clears it), so it is an unreliable proxy to gate on up front; the guidance is
  /// surfaced only when a read genuinely comes back empty rather than blocking the read path.
  static let accessibilityHint = "If reads consistently return nothing, the app's accessibility server is likely not running: set ApplicationAccessibilityEnabled (com.apple.Accessibility) before the app launches — e.g. `xcrun simctl spawn <UDID> defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -bool true` — then relaunch the app."

  /// Reads the frontmost application's element tree — probing `(x, y)` to discover its pid — and
  /// returns the root attribute dictionary with that pid. Shared by the whole-tree operations
  /// (describe-all, marker tap, marker set-value). Logs a warning when the walk hit the depth or node
  /// bound so a truncated tree is never passed off as complete.
  private func readFrontmostTree(anchorX x: Double, y: Double) async throws -> (root: [String: Any], pid: pid_t) {
    let session = try await self.session()
    let tree = try await session.applicationElementTree(
      anchorX: x, y: y,
      attributes: FBRemoteAutomationAXAttribute.fetchList,
      childrenAttribute: FBRemoteAutomationAXAttribute.children,
      maxDepth: Self.describeMaxDepth,
      maxNodes: Self.describeMaxNodes
    )
    guard let root = tree.root as? [String: Any] else {
      throw FBRemoteAutomationError.treeUnavailable(x: x, y: y)
    }
    if tree.truncated {
      _ = simulator?.logger?.log("Remote-automation read hit the bound (maxDepth \(Self.describeMaxDepth), maxNodes \(Self.describeMaxNodes)); the returned tree is truncated and incomplete.")
    }
    return (root, tree.processIdentifier)
  }

  /// Reads the element at a point and serializes it to the single-element accessibility schema,
  /// feeding a remote-backed `FBAXPlatformElement` through the same serializer as the legacy path.
  /// The element handle stays a disconnected local (received from the session and used once) so it
  /// never becomes a shareable value that would risk a data race across the session boundary.
  static func describeElement(atX x: Double, y: Double, using session: FBRemoteAutomationSession, keys: Set<FBAXKeys>) async throws -> FBJSONValue {
    guard let element = try await session.requestElement(atX: x, y: y) else {
      throw FBRemoteAutomationError.noElementAtPoint(x: x, y: y)
    }
    let raw = try await session.fetchAttributes(FBRemoteAutomationAXAttribute.fetchList, forElement: element)
    let attributes = (raw as? [String: Any]) ?? [:]
    let platformElement = FBRemoteAutomationPlatformElement(attributes: attributes, children: [], pid: 0)
    return FBSimulatorAccessibilitySerializer.formattedDescription(
      ofElement: platformElement,
      token: "",
      nestedFormat: false,
      keys: keys,
      collector: nil,
      coverageGrid: nil
    )
  }

  /// Serializes a remote attribute-dictionary tree (as returned by the session) into the schema,
  /// building a remote `FBAXPlatformElement` tree and running the shared recursive serializer. Each
  /// element is tagged with the frontmost app's real pid, discovered during the tree read.
  static func describeAllElements(fromTree tree: [String: Any], keys: Set<FBAXKeys>, nestedFormat: Bool, pid: pid_t) -> [FBJSONValue] {
    let root = buildPlatformElementTree(from: tree, pid: pid)
    return FBSimulatorAccessibilitySerializer.recursiveDescription(
      fromElement: root,
      token: "",
      nestedFormat: nestedFormat,
      keys: keys,
      collector: nil,
      coverageGrid: nil,
      seenPids: nil
    )
  }

  /// Recursively builds a remote `FBAXPlatformElement` from a nested attribute-dictionary node,
  /// tagging every node with the owning application's pid.
  static func buildPlatformElementTree(from node: [String: Any], pid: pid_t) -> FBRemoteAutomationPlatformElement {
    let childNodes = (node[FBRemoteAutomationAXAttribute.children] as? [[String: Any]]) ?? []
    let children = childNodes.map { buildPlatformElementTree(from: $0, pid: pid) }
    return FBRemoteAutomationPlatformElement(attributes: node, children: children, pid: pid)
  }

  /// The first serialized element whose `key` value equals `markerValue`, used by describe-by-marker.
  static func matchingElement(inElements elements: [FBJSONValue], markerValue: String, key: FBAXSearchableKey) -> FBJSONValue? {
    elements.first { element in
      guard case let .object(fields) = element, case let .string(value)? = fields[key.rawValue] else {
        return false
      }
      return value == markerValue
    }
  }

  /// The centre of the frame of the first serialized element whose `key` value equals `markerValue`.
  /// Shared by the marker-driven operations (tap, wait, set-value).
  static func frameCenter(inElements elements: [FBJSONValue], markerValue: String, key: FBAXSearchableKey) -> (x: Double, y: Double)? {
    func number(_ value: FBJSONValue?) -> Double? {
      switch value {
      case let .double(number): return number
      case let .int(number): return Double(number)
      default: return nil
      }
    }
    for element in elements {
      guard case let .object(fields) = element,
        case let .string(value)? = fields[key.rawValue], value == markerValue,
        case let .object(frame)? = fields[FBAXKeys.frameDict.rawValue],
        let x = number(frame["x"]), let y = number(frame["y"]),
        let width = number(frame["width"]), let height = number(frame["height"])
      else {
        continue
      }
      return (x + width / 2, y + height / 2)
    }
    return nil
  }

  /// Polls `probe` until it returns a non-nil value or `timeout` elapses (measured by `clock`),
  /// sleeping `pollInterval` between attempts. `clock`/`sleep` are injected for deterministic tests.
  static func pollUntilFound<T>(
    timeout: TimeInterval,
    pollInterval: TimeInterval,
    clock: () -> TimeInterval,
    sleep: (TimeInterval) async throws -> Void,
    probe: () async throws -> T?
  ) async throws -> T? {
    let deadline = clock() + timeout
    while true {
      if let value = try await probe() {
        return value
      }
      if clock() >= deadline {
        return nil
      }
      try await sleep(pollInterval)
    }
  }

  // MARK: - Session lifecycle

  private func session() async throws -> FBRemoteAutomationSession {
    if let sessionTask {
      return try await sessionTask.value
    }
    let simulator = self.simulator
    let task = Task { try await Self.makeSession(for: simulator) }
    sessionTask = task
    do {
      return try await task.value
    } catch {
      sessionTask = nil
      throw error
    }
  }

  private static func makeSession(for simulator: FBSimulator?) async throws -> FBRemoteAutomationSession {
    guard let simulator else {
      throw FBWeakTargetError.simulator
    }
    try XCTestBootstrapFrameworkLoader.allDependentFrameworks.loadPrivateFrameworks(simulator.logger)
    let socketPath: String
    do {
      socketPath =
        try await FBSimulatorXCTestCommands
        .commands(with: simulator)
        .testManagerDaemonSocketPath(envKey: remoteAutomationSockEnvKey)
    } catch {
      // testmanagerd only advertises this socket on runtimes that run the remote-automation
      // listener (iOS 27+), so a resolution failure means the backend is unavailable on this
      // simulator rather than a transient miss — surface that instead of the resolver's opaque
      // env-var timeout.
      throw FBRemoteAutomationError.unavailable(underlying: String(describing: error))
    }
    let connection = try FBRemoteAutomationConnection(
      socketPath: socketPath,
      queue: simulator.workQueue,
      logger: simulator.logger
    )
    // Let the DTX connection settle after `resume` before the first invocation; sending the
    // handshake immediately races the connection setup and the daemon drops the channel.
    try await Task.sleep(nanoseconds: 300_000_000)
    let session = FBRemoteAutomationSession(invoker: DTXRemoteInvoker(connection: connection), processIdentifier: 0)
    try await session.prime()
    return session
  }

  // MARK: - Event translation

  /// Translates a single-finger `FBSimulatorHIDEvent` (tap or swipe) into an `XCSynthesizedEventRecord`.
  ///
  /// A `.touch(.down)` starts the path (or, once started, moves it); a `.touch(.up)` lifts it; a
  /// `.delay` advances the time offset. A zero-delay tap is given a small nonzero lift offset so the
  /// daemon still registers it as a touch rather than a no-op.
  static func eventRecord(for event: FBSimulatorHIDEvent) throws -> Any {
    let steps = event.subEvents ?? [event]
    var path: FBRemoteAutomationPointerPath?
    var offset: TimeInterval = 0
    var downOffset: TimeInterval = 0
    for step in steps {
      switch step {
      case let .touch(direction, x, y):
        switch direction {
        case .down:
          if let path {
            path.move(toX: x, y: y, atOffset: offset)
          } else {
            let started = try FBRemoteAutomationPointerPath.pathForTouch(atX: x, y: y)
            started.pressDown(atOffset: offset)
            downOffset = offset
            path = started
          }
        case .up:
          path?.liftUp(atOffset: max(offset, downOffset + 0.05))
        @unknown default:
          break
        }
      case let .delay(interval):
        offset += interval
      default:
        break
      }
    }
    guard let path else {
      throw FBRemoteAutomationError.eventMissingTouchSteps
    }
    return try FBRemoteAutomationPayloads.eventRecord(withName: "remote-automation", pointerPaths: [path])
  }
}

public extension FBSimulator {
  /// The remote-automation surface, driving UI automation over the guest `testmanagerd`
  /// remote-automation channel without an `.xctest` bundle, runner, or build. Memoized per target.
  func remoteAutomation() throws -> FBSimulatorRemoteAutomation {
    commandCache.resolve { FBSimulatorRemoteAutomation.commands(with: self) }
  }
}

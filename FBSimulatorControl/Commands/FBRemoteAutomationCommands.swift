/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
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
public actor FBSimulatorRemoteAutomation: FBUIAutomation {

  private weak var simulator: FBSimulator?
  private var sessionTask: Task<FBRemoteAutomationSession, Error>?

  init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  /// Submits a synthesized input event (tap, swipe, …) over the remote-automation channel.
  public func sendHIDEvent(_ event: FBSimulatorHIDEvent) async throws {
    let session = try await self.session()
    let record = try Self.eventRecord(for: event)
    try await session.synthesizeEvent(record)
  }

  /// Presses a hardware button over the remote-automation channel's device-event selector
  /// (`_XCTD_performDeviceEvent:`), held for `duration` seconds. This actions a real HID button on
  /// the guest, unlike the legacy Indigo HOME/LOCK path which no-ops on Xcode 27. Reuses the shared
  /// `consumerHIDUsage` HID table (the same codes the DTUHID transport uses). Buttons with no single
  /// HID usage (Apple Pay — a double side-button press) throw `operationUnsupported`.
  public func pressButton(_ button: FBSimulatorHIDButton, duration: TimeInterval = 0) async throws {
    guard let usage = button.consumerHIDUsage else {
      throw FBRemoteAutomationError.operationUnsupported(operation: "Pressing the \(button.name) button")
    }
    let session = try await self.session()
    try await session.performDeviceEvent(page: UInt32(usage.page), usage: UInt32(usage.code), duration: duration)
  }

  // MARK: - FBUIAutomation

  /// Reads the element(s) named by `query` over the remote-automation channel and serializes them to
  /// the shared accessibility schema. `.point` reads the element at the coordinate; `.marker` finds
  /// the first frontmost-tree element whose `key` value equals the marker; `.frontmost` reads the
  /// whole tree. Marker and whole-tree reads probe the screen-centre anchor to discover the frontmost
  /// app's pid. `key` must be among the requested `keys` for a marker match to be found.
  public func describe(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse {
    let keys = options.keys ?? FBAXKeys.defaultSet
    switch query {
    case let .point(point):
      guard let response = try await hitTest(at: point, options: options) else {
        throw FBRemoteAutomationError.noElementAtPoint(x: Double(point.x), y: Double(point.y))
      }
      return response
    case let .marker(value, key, _):
      let tree = try await readFrontmostTree()
      let elements = FBAXTreeSerialization.describeAllElements(fromTree: tree.root, keys: keys, nestedFormat: false, pid: tree.pid)
      guard let match = FBAXTreeSerialization.matchingElement(inElements: elements, markerValue: value, key: key) else {
        throw FBRemoteAutomationError.elementNotFound(key: key.rawValue, value: value)
      }
      return FBAccessibilityElementsResponse(
        elements: match, profilingData: nil, frameCoverage: nil, additionalFrameCoverage: nil
      )
    case .frontmost:
      let tree = try await readFrontmostTree()
      let elements = FBAXTreeSerialization.describeAllElements(fromTree: tree.root, keys: keys, nestedFormat: options.nestedFormat, pid: tree.pid, filter: options.filter)
      return FBAccessibilityElementsResponse(
        elements: .array(elements), profilingData: nil, frameCoverage: nil, additionalFrameCoverage: nil
      )
    case let .application(pid):
      let tree = try await readApplicationTree(forPid: pid)
      let elements = FBAXTreeSerialization.describeAllElements(fromTree: tree.root, keys: keys, nestedFormat: options.nestedFormat, pid: tree.pid, filter: options.filter)
      return FBAccessibilityElementsResponse(
        elements: .array(elements), profilingData: nil, frameCoverage: nil, additionalFrameCoverage: nil
      )
    }
  }

  /// Reads the element at `point` via a targeted remote hit-test, or `nil` when the point is empty.
  public func hitTest(
    at point: CGPoint,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse? {
    let keys = options.keys ?? FBAXKeys.defaultSet
    let session = try await self.session()
    guard let element = try await Self.hitTestElement(atX: Double(point.x), y: Double(point.y), using: session, keys: keys) else {
      return nil
    }
    return FBAccessibilityElementsResponse(
      elements: element, profilingData: nil, frameCoverage: nil, additionalFrameCoverage: nil
    )
  }

  // MARK: - Anchor

  /// The screen-centre point used as the *fallback* anchor to probe the frontmost app's pid when the
  /// AX frontmost query is unavailable (any on-screen point over the frontmost app works; centre
  /// avoids edges/status bar).
  private func anchorPoint() -> (x: Double, y: Double) {
    let info = simulator?.screenInfo
    return Self.anchorPoint(widthPixels: info?.widthPixels ?? 828, heightPixels: info?.heightPixels ?? 1792, scale: info?.scale ?? 2)
  }

  /// The centre of a screen of the given pixel dimensions, in points. A pure function so the anchor
  /// arithmetic (and the guard against a zero scale) is unit-testable without a target.
  static func anchorPoint(widthPixels: UInt, heightPixels: UInt, scale: Float) -> (x: Double, y: Double) {
    let scale = scale > 0 ? Double(scale) : 1
    return (Double(widthPixels) / scale / 2.0, Double(heightPixels) / scale / 2.0)
  }

  /// Taps the element named by `query`. `.point` taps the coordinate directly; `.marker` finds the
  /// element in the frontmost tree and taps its frame centre. `.frontmost` is not a tappable target
  /// over remote automation. `expectedValue`/`expectedKey` are accessibility-only and ignored here.
  public func tap(
    _ query: FBAccessibilityElementQuery,
    expectedValue: String?,
    expectedKey: FBAXSearchableKey
  ) async throws {
    switch query {
    case let .point(point):
      try await sendHIDEvent(.tapAt(x: Double(point.x), y: Double(point.y)))
    case let .marker(markerValue, key, _):
      let tree = try await readFrontmostTree()
      let elements = FBAXTreeSerialization.describeAllElements(fromTree: tree.root, keys: FBAXKeys.defaultSet, nestedFormat: false, pid: tree.pid)
      guard let center = FBAXTreeSerialization.frameCenter(inElements: elements, markerValue: markerValue, key: key) else {
        throw FBRemoteAutomationError.elementNotFound(key: key.rawValue, value: markerValue)
      }
      let session = try await self.session()
      let record = try Self.eventRecord(for: .tapAt(x: center.x, y: center.y))
      try await session.synthesizeEvent(record)
    case .frontmost, .application:
      throw FBRemoteAutomationError.pointOrMarkerRequired(operation: "A tap")
    }
  }

  /// Polls the frontmost app tree until the element named by a `.marker` query appears, or throws when
  /// `timeout` elapses. `.point`/`.frontmost` are not waitable. The screen-centre anchor is probed to
  /// discover the frontmost app's pid.
  public func wait(
    _ query: FBAccessibilityElementQuery,
    timeout: TimeInterval,
    pollInterval: TimeInterval
  ) async throws {
    guard case let .marker(markerValue, key, _) = query else {
      throw FBRemoteAutomationError.markerRequired(operation: "Waiting")
    }
    let session = try await self.session()
    // Resolve the frontmost app's pid once via the AX window-server query and anchor every poll on
    // it, so a system modal / launch chrome at the screen centre can't hijack the wait — and the
    // poll closure captures only Sendable values (pid + session), never the actor. Fall back to the
    // midpoint hit-test only when the AX pid is unavailable.
    let pid = await frontmostApplicationPid()
    let fallbackAnchor = pid > 0 ? nil : anchorPoint()
    let found = try await FBUIAutomationPolling.pollUntilFound(
      timeout: timeout,
      pollInterval: pollInterval,
      clock: { Date().timeIntervalSinceReferenceDate },
      sleep: { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) { () -> Bool? in
      // A poll reads the tree directly (rather than via `readFrontmostTree`) so a missing tree retries
      // instead of throwing, and the truncation warning is not logged on every poll iteration.
      let tree: FBRemoteAutomationElementTree
      if pid > 0 {
        tree = try await session.applicationElementTree(
          forPid: pid,
          attributes: FBRemoteAutomationAXAttribute.fetchList,
          childrenAttribute: FBRemoteAutomationAXAttribute.children,
          maxDepth: Self.describeMaxDepth,
          maxNodes: Self.describeMaxNodes
        )
      } else if let fallbackAnchor {
        tree = try await session.applicationElementTree(
          anchorX: fallbackAnchor.x, y: fallbackAnchor.y,
          attributes: FBRemoteAutomationAXAttribute.fetchList,
          childrenAttribute: FBRemoteAutomationAXAttribute.children,
          maxDepth: Self.describeMaxDepth,
          maxNodes: Self.describeMaxNodes
        )
      } else {
        return nil
      }
      guard let root = tree.root as? [String: Any] else { return nil }
      let elements = FBAXTreeSerialization.describeAllElements(fromTree: root, keys: FBAXKeys.defaultSet, nestedFormat: false, pid: tree.processIdentifier)
      return FBAXTreeSerialization.frameCenter(inElements: elements, markerValue: markerValue, key: key) != nil ? true : nil
    }
    if found == nil {
      throw FBRemoteAutomationError.timedOut(key: key.rawValue, value: markerValue, timeout: timeout)
    }
  }

  /// Scrolls the element named by `query`. Not yet supported over remote automation; the accessibility
  /// backend handles scroll.
  public func scroll(_ query: FBAccessibilityElementQuery, direction: FBAccessibilityScrollDirection) async throws {
    throw FBRemoteAutomationError.operationUnsupported(operation: "Scroll")
  }

  /// The frame of the element named by `query`. Not yet supported over remote automation; the
  /// accessibility backend serves element geometry.
  public func frame(_ query: FBAccessibilityElementQuery) async throws -> CGRect {
    throw FBRemoteAutomationError.operationUnsupported(operation: "Reading an element frame")
  }

  /// Sets `value` on the element named by `query`. `.point` targets the coordinate; `.marker` finds
  /// the element in the frontmost tree and targets its centre. `.frontmost` is not a set-value target.
  public func setValue(_ value: String, for query: FBAccessibilityElementQuery) async throws {
    switch query {
    case let .point(point):
      let session = try await self.session()
      try await session.setValue(value, atX: Double(point.x), y: Double(point.y), valueAttribute: FBRemoteAutomationAXAttribute.value)
    case let .marker(markerValue, key, _):
      let tree = try await readFrontmostTree()
      let elements = FBAXTreeSerialization.describeAllElements(fromTree: tree.root, keys: FBAXKeys.defaultSet, nestedFormat: false, pid: tree.pid)
      guard let center = FBAXTreeSerialization.frameCenter(inElements: elements, markerValue: markerValue, key: key) else {
        throw FBRemoteAutomationError.elementNotFound(key: key.rawValue, value: markerValue)
      }
      let session = try await self.session()
      try await session.setValue(value, atX: center.x, y: center.y, valueAttribute: FBRemoteAutomationAXAttribute.value)
    case .frontmost, .application:
      throw FBRemoteAutomationError.pointOrMarkerRequired(operation: "Setting a value")
    }
  }

  // MARK: - Reads

  private static let describeMaxDepth = 50
  private static let describeMaxNodes = 3000

  /// Resolves the frontmost application's pid via the CoreSimulator AX path — a window-server
  /// frontmost query, not a screen hit-test — so the remote read anchors on the real app rather than
  /// whatever process owns the centre pixel (a system modal, launch-transition chrome, or an empty
  /// point). Returns 0 when the AX path can't resolve it, so the caller falls back to the midpoint.
  private func frontmostApplicationPid() async -> pid_t {
    guard let simulator else { return 0 }
    do {
      let element = try await simulator.resolveElement(for: .frontmost)
      defer { element.close() }
      return element.processIdentifier
    } catch {
      return 0
    }
  }

  /// Reads the frontmost app's element tree, anchoring on the AX-resolved pid; falls back to the
  /// screen-midpoint hit-test only when the AX pid is unavailable. Shared by `readFrontmostTree` and
  /// the `wait` poll.
  private func frontmostTree(using session: FBRemoteAutomationSession) async throws -> FBRemoteAutomationElementTree {
    let pid = await frontmostApplicationPid()
    if pid > 0 {
      return try await session.applicationElementTree(
        forPid: pid,
        attributes: FBRemoteAutomationAXAttribute.fetchList,
        childrenAttribute: FBRemoteAutomationAXAttribute.children,
        maxDepth: Self.describeMaxDepth,
        maxNodes: Self.describeMaxNodes
      )
    }
    let anchor = anchorPoint()
    return try await session.applicationElementTree(
      anchorX: anchor.x, y: anchor.y,
      attributes: FBRemoteAutomationAXAttribute.fetchList,
      childrenAttribute: FBRemoteAutomationAXAttribute.children,
      maxDepth: Self.describeMaxDepth,
      maxNodes: Self.describeMaxNodes
    )
  }

  /// Reads the frontmost application's element tree (pid-anchored, midpoint fallback) and returns the
  /// root attribute dictionary with the owning pid. Shared by the whole-tree operations (describe-all,
  /// marker tap, marker set-value). Logs a warning when the walk hit the depth or node bound so a
  /// truncated tree is never passed off as complete.
  private func readFrontmostTree() async throws -> (root: [String: Any], pid: pid_t) {
    let session = try await self.session()
    let tree = try await frontmostTree(using: session)
    guard let root = tree.root as? [String: Any] else {
      let anchor = anchorPoint()
      throw FBRemoteAutomationError.treeUnavailable(x: anchor.x, y: anchor.y)
    }
    if tree.truncated {
      _ = simulator?.logger?.log("Remote-automation read hit the bound (maxDepth \(Self.describeMaxDepth), maxNodes \(Self.describeMaxNodes)); the returned tree is truncated and incomplete.")
    }
    return (root, tree.processIdentifier)
  }

  /// Reads a specific application's element tree, anchored directly on `pid` — no frontmost resolution
  /// and no hit-test. Throws `applicationUnavailable` when the pid yields no tree (a dead pid, or the
  /// app's accessibility server hasn't started).
  private func readApplicationTree(forPid pid: pid_t) async throws -> (root: [String: Any], pid: pid_t) {
    let session = try await self.session()
    let tree = try await session.applicationElementTree(
      forPid: pid,
      attributes: FBRemoteAutomationAXAttribute.fetchList,
      childrenAttribute: FBRemoteAutomationAXAttribute.children,
      maxDepth: Self.describeMaxDepth,
      maxNodes: Self.describeMaxNodes
    )
    guard let root = tree.root as? [String: Any] else {
      throw FBRemoteAutomationError.applicationUnavailable(pid: pid)
    }
    if tree.truncated {
      _ = simulator?.logger?.log("Remote-automation read hit the bound (maxDepth \(Self.describeMaxDepth), maxNodes \(Self.describeMaxNodes)); the returned tree is truncated and incomplete.")
    }
    return (root, tree.processIdentifier)
  }

  /// Reads the element at a point and serializes it to the single-element accessibility schema,
  /// feeding a remote-backed `FBAXPlatformElement` through the same serializer as the legacy path, or
  /// `nil` when no element sits at the point (a valid empty hit-test result, not a failure). The
  /// element handle stays a disconnected local (received from the session and used once) so it never
  /// becomes a shareable value that would risk a data race across the session boundary.
  static func hitTestElement(atX x: Double, y: Double, using session: FBRemoteAutomationSession, keys: Set<FBAXKeys>) async throws -> FBJSONValue? {
    guard let element = try await session.requestElement(atX: x, y: y) else {
      return nil
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

  // MARK: - Session lifecycle

  // The session is expensive to establish (see `makeSession`: framework load + DTX handshake +
  // settle), so it is built once and memoized on this actor; every operation reuses it. Callers
  // amortize by holding this actor (via the memoized `simulator.remoteAutomation()`) across
  // operations rather than re-creating it per call — one session per process, not per command.
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
    return try await FBRemoteAutomationSession.connected(invoker: DTXRemoteInvoker(connection: connection), processIdentifier: 0)
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
  ///
  /// **Reuse this instance to amortize the session cost.** The first operation establishes the
  /// underlying `FBRemoteAutomationSession` — socket connect, private-framework load, DTX handshake,
  /// and settle (~1.8–4.75s) — which is then memoized and reused for every later operation on this
  /// target. A caller that holds one `FBSimulator` (the idb companion, or a persistent driver) pays
  /// that cost once; a one-shot CLI invocation that exits after a single command re-establishes the
  /// whole session every time. Prefer a long-lived process for repeated reads/actions.
  func remoteAutomation() throws -> FBSimulatorRemoteAutomation {
    commandCache.resolve { FBSimulatorRemoteAutomation(simulator: self) }
  }
}

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
/// Reached through `FBSimulator.remoteAutomation()`, which returns a fresh instance each call; hold
/// one to reuse it. The underlying `FBRemoteAutomationSession` — socket connect, framework preload,
/// handshake — is built and primed once on first use of an instance and reused; a failed build clears
/// the memo so a later call retries. An actor so the session is established exactly once under
/// concurrent callers on that instance, without a lock across suspension points.
public actor FBSimulatorRemoteAutomation: FBUIAutomation {

  private weak var simulator: FBSimulator?
  private var sessionTask: Task<FBRemoteAutomationSession, Error>?
  private var sessionGeneration = 0

  init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  /// Submits a synthesized input event (tap, swipe, …) over the remote-automation channel.
  public func sendHIDEvent(_ event: FBSimulatorHIDEvent) async throws {
    // The record is built inside the session closure: it is not Sendable, so it must be created and
    // consumed in the same isolation region.
    try await withSession { session in
      try await session.synthesizeEvent(try Self.eventRecord(for: event))
    }
  }

  /// Presses a hardware button over the remote-automation channel's device-event selector
  /// (`_XCTD_performDeviceEvent:`), held for `duration` seconds. This actions a real HID button on
  /// the guest, unlike the legacy Indigo HOME/LOCK path which no-ops on Xcode 27. Reuses the shared
  /// `consumerHIDUsage` HID table (the same codes the DTUHID transport uses). Buttons with no single
  /// HID usage (Apple Pay — a double side-button press) throw `operationUnsupported`.
  public func pressButton(_ button: FBSimulatorHIDButton, duration: TimeInterval = 0) async throws {
    guard let usage = button.consumerHIDUsage else {
      throw FBUIAutomationError.operationUnsupported(backend: .remoteAutomation, operation: "Pressing the \(button.name) button")
    }
    try await withSession { try await $0.performDeviceEvent(page: UInt32(usage.page), usage: UInt32(usage.code), duration: duration) }
  }

  // MARK: - FBUIAutomation

  /// Reads the element(s) named by `query` over the remote-automation channel and serializes them to
  /// the shared accessibility schema. `.point` reads the element at the coordinate; `.marker` finds
  /// the first frontmost-tree element whose `key` value contains the marker; `.frontmost` reads the
  /// whole tree. Marker and whole-tree reads resolve the frontmost app's pid, falling back to a
  /// screen-centre probe. `key` must be among the requested `keys` for a marker match to be found,
  /// because the match runs over the serialized element rather than the raw tree.
  public func describe(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse {
    let keys = options.keys
    switch query {
    case let .point(point):
      guard let response = try await hitTest(at: point, options: options) else {
        throw FBUIAutomationError.noElementAtPoint(backend: .remoteAutomation, x: Double(point.x), y: Double(point.y))
      }
      return response
    case let .marker(value, key, _):
      let tree = try await readFrontmostTree()
      let elements = FBAXTreeSerialization.describeAllElements(fromTree: tree.root, keys: keys, nestedFormat: false, pid: tree.pid)
      guard let match = FBAXTreeSerialization.matchingElement(inElements: elements, markerValue: value, key: key) else {
        throw FBUIAutomationError.elementNotFound(backend: .remoteAutomation, key: key.rawValue, value: value)
      }
      return FBAccessibilityElementsResponse(
        elements: match
      )
    case .frontmost:
      let tree = try await readFrontmostTree()
      let elements = FBAXTreeSerialization.describeAllElements(fromTree: tree.root, keys: keys, nestedFormat: options.nestedFormat, pid: tree.pid, filter: options.filter)
      return FBAccessibilityElementsResponse(
        elements: .array(elements)
      )
    case let .application(pid):
      let tree = try await readApplicationTree(forPid: pid)
      let elements = FBAXTreeSerialization.describeAllElements(fromTree: tree.root, keys: keys, nestedFormat: options.nestedFormat, pid: tree.pid, filter: options.filter)
      return FBAccessibilityElementsResponse(
        elements: .array(elements)
      )
    }
  }

  /// Reads the element at `point` via a targeted remote hit-test, or `nil` when the point is empty.
  public func hitTest(
    at point: CGPoint,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse? {
    let keys = options.keys
    let hit = try await withSession { session in
      try await Self.hitTestElement(atX: Double(point.x), y: Double(point.y), using: session, keys: keys)
    }
    guard let element = hit else {
      return nil
    }
    return FBAccessibilityElementsResponse(
      elements: element
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
        throw FBUIAutomationError.elementNotFound(backend: .remoteAutomation, key: key.rawValue, value: markerValue)
      }
      try await withSession { session in
        try await session.synthesizeEvent(try Self.eventRecord(for: .tapAt(x: center.x, y: center.y)))
      }
    case .frontmost, .application:
      throw FBUIAutomationError.pointOrMarkerRequired(backend: .remoteAutomation, operation: "A tap")
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
    let (session, generation) = try await self.session()
    // Resolve the frontmost app's pid once via the AX window-server query and anchor every poll on
    // it, so a system modal / launch chrome at the screen centre can't hijack the wait — and the
    // poll closure captures only Sendable values (pid + session), never the actor. Fall back to the
    // midpoint hit-test only when the AX pid is unavailable.
    let pid = await frontmostApplicationPid()
    let fallbackAnchor = pid > 0 ? nil : anchorPoint()
    // A wait holds one session for its whole duration, so if that session dies mid-wait the failure
    // propagates out and the memo must be dropped — otherwise the next operation reuses the corpse.
    do {
      try await pollForMarker(query, session: session, pid: pid, fallbackAnchor: fallbackAnchor, timeout: timeout, pollInterval: pollInterval)
    } catch {
      if sessionGeneration == generation {
        sessionTask = nil
      }
      throw error
    }
  }

  private func pollForMarker(
    _ query: FBAccessibilityElementQuery,
    session: FBRemoteAutomationSession,
    pid: pid_t,
    fallbackAnchor: (x: Double, y: Double)?,
    timeout: TimeInterval,
    pollInterval: TimeInterval
  ) async throws {
    try await FBUIAutomationPolling.waitForMarker(
      query, backend: .remoteAutomation, timeout: timeout, pollInterval: pollInterval
    ) { markerValue, key, _ in
      // A poll reads the tree directly (rather than via `readFrontmostTree`) so a missing tree retries
      // instead of throwing, and the truncation warning is not logged on every poll iteration.
      let tree: FBRemoteAutomationElementTree
      if pid > 0 {
        tree = try await session.applicationElementTree(
          forPid: pid,
          attributes: FBRemoteAutomationAXAttribute.fetchList,
          childrenAttribute: FBRemoteAutomationAXAttribute.children,
          maxDepth: FBAXTreeSerialization.maxReadDepth,
          maxNodes: FBAXTreeSerialization.maxReadNodes
        )
      } else if let fallbackAnchor {
        tree = try await session.applicationElementTree(
          anchorX: fallbackAnchor.x, y: fallbackAnchor.y,
          attributes: FBRemoteAutomationAXAttribute.fetchList,
          childrenAttribute: FBRemoteAutomationAXAttribute.children,
          maxDepth: FBAXTreeSerialization.maxReadDepth,
          maxNodes: FBAXTreeSerialization.maxReadNodes
        )
      } else {
        return nil
      }
      guard let root = tree.root as? [String: Any] else { return nil }
      let elements = FBAXTreeSerialization.describeAllElements(fromTree: root, keys: FBAXKeys.defaultSet, nestedFormat: false, pid: tree.processIdentifier)
      return FBAXTreeSerialization.frameCenter(inElements: elements, markerValue: markerValue, key: key) != nil ? true : nil
    }
  }

  /// Scrolls the element named by `query`. Not yet supported over remote automation; the accessibility
  /// backend handles scroll.
  public func scroll(_ query: FBAccessibilityElementQuery, direction: FBAccessibilityScrollDirection) async throws {
    throw FBUIAutomationError.operationUnsupported(backend: .remoteAutomation, operation: "Scroll")
  }

  /// The frame of the element named by `query`. Not yet supported over remote automation; the
  /// accessibility backend serves element geometry.
  public func frame(_ query: FBAccessibilityElementQuery) async throws -> CGRect {
    throw FBUIAutomationError.operationUnsupported(backend: .remoteAutomation, operation: "Reading an element frame")
  }

  /// Sets `value` on the element named by `query`. `.point` targets the coordinate; `.marker` finds
  /// the element in the frontmost tree and targets its centre. `.frontmost` is not a set-value target.
  public func setValue(_ value: String, for query: FBAccessibilityElementQuery) async throws {
    switch query {
    case let .point(point):
      try await withSession { try await $0.setValue(value, atX: Double(point.x), y: Double(point.y), valueAttribute: FBRemoteAutomationAXAttribute.value) }
    case let .marker(markerValue, key, _):
      let tree = try await readFrontmostTree()
      let elements = FBAXTreeSerialization.describeAllElements(fromTree: tree.root, keys: FBAXKeys.defaultSet, nestedFormat: false, pid: tree.pid)
      guard let center = FBAXTreeSerialization.frameCenter(inElements: elements, markerValue: markerValue, key: key) else {
        throw FBUIAutomationError.elementNotFound(backend: .remoteAutomation, key: key.rawValue, value: markerValue)
      }
      try await withSession { try await $0.setValue(value, atX: center.x, y: center.y, valueAttribute: FBRemoteAutomationAXAttribute.value) }
    case .frontmost, .application:
      throw FBUIAutomationError.pointOrMarkerRequired(backend: .remoteAutomation, operation: "Setting a value")
    }
  }

  // MARK: - Reads

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
        maxDepth: FBAXTreeSerialization.maxReadDepth,
        maxNodes: FBAXTreeSerialization.maxReadNodes
      )
    }
    let anchor = anchorPoint()
    return try await session.applicationElementTree(
      anchorX: anchor.x, y: anchor.y,
      attributes: FBRemoteAutomationAXAttribute.fetchList,
      childrenAttribute: FBRemoteAutomationAXAttribute.children,
      maxDepth: FBAXTreeSerialization.maxReadDepth,
      maxNodes: FBAXTreeSerialization.maxReadNodes
    )
  }

  /// Reads the frontmost application's element tree (pid-anchored, midpoint fallback) and returns the
  /// root attribute dictionary with the owning pid. Shared by the whole-tree operations (describe-all,
  /// marker tap, marker set-value). Logs a warning when the walk hit the depth or node bound so a
  /// truncated tree is never passed off as complete.
  private func readFrontmostTree() async throws -> (root: [String: Any], pid: pid_t) {
    let tree = try await withSession { try await frontmostTree(using: $0) }
    guard let root = tree.root as? [String: Any] else {
      let anchor = anchorPoint()
      throw FBRemoteAutomationError.treeUnavailable(x: anchor.x, y: anchor.y)
    }
    if tree.truncated {
      _ = simulator?.logger?.log("Remote-automation read hit the bound (maxDepth \(FBAXTreeSerialization.maxReadDepth), maxNodes \(FBAXTreeSerialization.maxReadNodes)); the returned tree is truncated and incomplete.")
    }
    return (root, tree.processIdentifier)
  }

  /// Reads a specific application's element tree, anchored directly on `pid` — no frontmost resolution
  /// and no hit-test. Throws `applicationUnavailable` when the pid yields no tree (a dead pid, or the
  /// app's accessibility server hasn't started).
  private func readApplicationTree(forPid pid: pid_t) async throws -> (root: [String: Any], pid: pid_t) {
    let tree = try await withSession { session in
      try await session.applicationElementTree(
        forPid: pid,
        attributes: FBRemoteAutomationAXAttribute.fetchList,
        childrenAttribute: FBRemoteAutomationAXAttribute.children,
        maxDepth: FBAXTreeSerialization.maxReadDepth,
        maxNodes: FBAXTreeSerialization.maxReadNodes
      )
    }
    guard let root = tree.root as? [String: Any] else {
      throw FBUIAutomationError.applicationUnavailable(backend: .remoteAutomation, pid: pid)
    }
    if tree.truncated {
      _ = simulator?.logger?.log("Remote-automation read hit the bound (maxDepth \(FBAXTreeSerialization.maxReadDepth), maxNodes \(FBAXTreeSerialization.maxReadNodes)); the returned tree is truncated and incomplete.")
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
  // amortize by holding this instance across operations rather than re-creating it per call — one
  // session per held instance, torn down when the instance is released.

  /// Runs `body` against the memoized session, dropping that session if the operation fails.
  ///
  /// Without this a session that dies mid-lifetime — the daemon restarted, the simulator shut down,
  /// the channel dropped — is never replaced, because a memo that resolved successfully was only ever
  /// cleared on an establish failure. Every later operation then reuses the corpse and the instance is
  /// wedged for good.
  ///
  /// Deliberately no automatic retry: remote operations include writes (tap, set-value, device
  /// events), and replaying one that may already have been applied could double-apply it. Dropping the
  /// dead session is enough — the failure is reported, and the *next* operation establishes a fresh
  /// one. The read transport, whose operations are all idempotent, does retry.
  private func withSession<T>(_ body: (FBRemoteAutomationSession) async throws -> T) async throws -> T {
    let (session, generation) = try await self.session()
    do {
      return try await body(session)
    } catch {
      // Compare-and-clear: only drop the memo if it still holds the session that just failed. This
      // actor is reentrant, so a concurrent caller may already have replaced it, and clearing
      // unconditionally would discard a healthy session and re-run the expensive handshake.
      if sessionGeneration == generation {
        sessionTask = nil
      }
      throw error
    }
  }

  /// The memoized session and the generation that produced it, establishing one on first use. The
  /// generation lets a caller drop only the session it actually saw fail.
  private func session() async throws -> (session: FBRemoteAutomationSession, generation: Int) {
    if let sessionTask {
      let generation = sessionGeneration
      return (try await sessionTask.value, generation)
    }
    sessionGeneration += 1
    let generation = sessionGeneration
    let simulator = self.simulator
    let task = Task { try await Self.makeSession(for: simulator) }
    sessionTask = task
    do {
      return (try await task.value, generation)
    } catch {
      if sessionGeneration == generation {
        sessionTask = nil
      }
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
  /// remote-automation channel without an `.xctest` bundle, runner, or build.
  ///
  /// **Hold the returned instance to amortize the session cost.** Each call returns a fresh
  /// `FBSimulatorRemoteAutomation` that owns its own `FBRemoteAutomationSession`; the first operation
  /// on an instance establishes it — socket connect, private-framework load, DTX handshake, and settle
  /// (~1.8–4.75s) — and every later operation on that same instance reuses it. A long-lived caller
  /// (the idb companion, or a persistent driver) holds one instance and pays that cost once; dropping
  /// the instance tears the session down. A one-shot CLI invocation establishes the session once and
  /// lets it go on exit.
  func remoteAutomation() throws -> FBSimulatorRemoteAutomation {
    FBSimulatorRemoteAutomation(simulator: self)
  }
}

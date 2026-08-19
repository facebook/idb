/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

/// The `FBUIAutomation` backend that reads via the `SimulatorFrameworkBridge` guest `accessibility`
/// service — an in-simulator accessibility client, with no automation daemon, DTX channel, or test
/// bundle. XCUI-grade like `.remoteAutomation`, but light like `.accessibility`.
///
/// One-shot per read: each verb resolves the target pid (frontmost via the CoreSimulator AX path, or a
/// given application pid), spawns the guest with `accessibility describe --pid <pid>`, parses its JSON
/// tree, and feeds it through the **same** serializer path the `testmanagerd` backend uses
/// (`FBRemoteAutomationPlatformElement` -> `FBAXNodeSerializer`), because the guest
/// emits the identical `XC_kAXXC*` node shape. The output schema is therefore byte-identical across
/// the two backends and needs no new serialization code.
///
/// Writes are semantic accessibility actions, not synthesized input: the guest hands the AX runtime a
/// press or a scroll and the element's own implementation decides what happens, which is the whole
/// reason to use this rather than the HID path. They are addressed by point, because a one-shot guest
/// exits between requests and so cannot hold an element handle across one; a `.marker` write resolves
/// its point host-side from a tree read and carries an assertion the guest re-checks, so the write
/// cannot land on whatever moved under the point in between.
///
// SAFETY: immutable after init — it holds the target and a transport; the persistent transport is an
// actor and the one-shot transport is a stateless value, and the verb logic keeps no mutable state.
// `Sendable` lets a long-lived caller (e.g. `ui shell`) hold one warm reader across reads.
// patternlint-disable-next-line unchecked-sendable
final class FBAXBridgeUIAutomation: FBAXTreeReader, @unchecked Sendable {

  /// What this read asks the guest to do about accessibility automation mode.
  ///
  /// Tri-state, matching the guest: `true` asserts the mode, `false` asserts it off, `nil` observes
  /// without touching the device. Selecting the axbridge lane by name yields `true`, because that is the
  /// mode a UI-test host puts an application into and reading without it means UIKit collapses subtrees
  /// and can serve cached children describing a screen that is no longer displayed.
  ///
  /// Carried per instance rather than as a constant so a caller can have both answers on one device in
  /// one process — which is what measuring the mode's cost needs, and what showing the fault and the fix
  /// without swapping binaries needs.
  let requestedAutomationMode: Bool?

  private let simulator: FBSimulator
  private let transport: any FBAXBridgeTransport

  /// The transport lifecycle this reader was vended for. Held only so `backend` reports the case the
  /// caller selected; the injected transport already encodes the behavioural difference.
  private let persistence: FBAXBridgePersistence

  /// How frontmost reads resolve the foreground app. Defaults to the authoritative `.windowServer`; a
  /// caller (e.g. sime2e) can select the positional `.centerPoint` or `.runningBoard`.
  private let frontmostMethod: FBAXBridgeFrontmostMethod

  init(
    simulator: FBSimulator,
    transport: any FBAXBridgeTransport,
    persistence: FBAXBridgePersistence,
    frontmostMethod: FBAXBridgeFrontmostMethod = .windowServer,
    automationMode: Bool? = true
  ) {
    self.simulator = simulator
    self.transport = transport
    self.persistence = persistence
    self.frontmostMethod = frontmostMethod
    self.requestedAutomationMode = automationMode
  }

  // MARK: - Reads

  func describe(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse {
    try await describeTree(query, options: options)
  }

  nonisolated var backend: FBUIAutomationBackend {
    .axBridge(
      persistence: persistence, frontmostMethod: frontmostMethod, automationMode: requestedAutomationMode)
  }

  /// Re-raises the two transport-level failures that are really facts about the application as their
  /// backend-neutral cases, so a caller holding `any FBUIAutomation` sees the same typed error for a dead
  /// or wedged app regardless of which backend served the read (the remote backend throws the neutral
  /// case directly). Every other bridge error is about this transport and passes through untouched.
  private func translatingSeamErrors<T>(_ body: () async throws -> T) async throws -> T {
    do {
      return try await body()
    } catch let FBAXBridgeError.applicationUnavailable(pid) {
      throw FBUIAutomationError.applicationUnavailable(backend: backend, pid: pid)
    } catch let FBAXBridgeError.applicationNotResponding(pid) {
      throw FBUIAutomationError.applicationNotResponding(backend: backend, pid: pid)
    }
  }

  /// Reads the whole bounded attribute tree a query targets, through the configured transport (one-shot
  /// spawn or persistent socket). `.application` reads the named pid; every other query is a frontmost
  /// read served by a single fused guest query — the guest resolves the frontmost app (system-wide
  /// hit-test at the screen-centre anchor) and reads its tree in one IPC hop, reporting the pid it
  /// resolved. No host-side CoreSimulator query and no separate pid round-trip. `.point` does not use
  /// this — it uses the targeted `transport.hitTest`.
  func readRawTree(
    for query: FBAccessibilityElementQuery,
    attributes: [String]?,
    explainUnreachable: Bool,
    strategy: FBAXTraversalStrategy
  ) async throws -> FBAXTreeRead {
    try await translatingSeamErrors {
      if case let .application(pid) = query {
        let response = try await transport.read(
          pid: pid, maxDepth: FBAXReadLimits.maxReadDepth, maxNodes: FBAXReadLimits.maxReadNodes,
          attributes: attributes, explainUnreachable: explainUnreachable, strategy: strategy,
          automationMode: requestedAutomationMode
        )
        return try FBAXTreeRead(wholeTreeResponse: response, pid: pid)
      }
      let anchor = frontmostAnchor()
      let response = try await transport.readFrontmost(
        x: anchor.x, y: anchor.y, maxDepth: FBAXReadLimits.maxReadDepth, maxNodes: FBAXReadLimits.maxReadNodes,
        method: frontmostMethod, attributes: attributes, explainUnreachable: explainUnreachable,
        strategy: strategy, automationMode: requestedAutomationMode
      )
      return try FBAXTreeRead(frontmostResponse: response, method: frontmostMethod)
    }
  }

  func hitTest(
    at point: CGPoint,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse? {
    try await translatingSeamErrors {
      // A single system-wide guest hit-test resolves the element at the point and its owning app
      // in-guest — no host-side CoreSimulator frontmost query, one IPC hop. `.point` is positional, so
      // a system-wide hit-test is exactly its semantics (unlike a whole-tree read of "frontmost").
      let response = try await transport.hitTest(
        x: Double(point.x), y: Double(point.y), attributes: FBAXWire.Node.fetchList(for: options.serializationKeys)
      )
      guard let hit = try FBAXTreeRead(hitTestResponse: response) else {
        return nil
      }
      let element = FBAXTreeWalk.buildPlatformElementTree(from: hit.tree, pid: hit.pid)
      var formatted = FBAXNodeSerializer.formattedDescription(
        ofElement: element, token: "", nestedFormat: options.nestedFormat, keys: options.serializationKeys, collector: nil
      )
      // The hit element is the one the caller named, so it is exempt; its descendants honour the filter.
      if let children = formatted.children {
        formatted.children = options.filter.apply(to: children)
      }
      return FBAccessibilityElementsResponse(elements: .single(formatted))
        .withProvenance(backend: backend.name, target: .point(point))
    }
  }

  func wait(
    _ query: FBAccessibilityElementQuery,
    timeout: TimeInterval,
    pollInterval: TimeInterval
  ) async throws {
    try await FBUIAutomationPolling.waitForMarker(
      query, backend: backend, timeout: timeout, pollInterval: pollInterval
    ) { markerValue, key, _ in
      // Re-read the frontmost tree each poll (one fused guest query) so an app that launches mid-wait is
      // picked up — no separate pid resolution.
      do {
        // A poll reads the raw tree directly (not through `describeTree`), so `warnIfTruncated` is not
        // called on every poll iteration — matching the describe-path-only warning.
        let read = try await self.readRawTree(for: .frontmost, attributes: nil, explainUnreachable: false, strategy: .viewHierarchy)
        let elements = FBAXTreeWalk.describeAllElements(
          fromTree: read.tree, keys: FBAXKeys.defaultSet.union([key.serializationKey]), nestedFormat: false, pid: read.pid
        )
        return FBAXTreeWalk.matchingElement(inElements: elements, markerValue: markerValue, key: key) != nil ? true : nil
      } catch let error as FBAXBridgeError {
        // Which failures are worth polling through is `isTransientWhileWaitingForAMarker`; anything else
        // (and any unexpected non-bridge error) ends the wait at once rather than burning the timeout.
        guard error.isTransientWhileWaitingForAMarker else {
          throw error
        }
        return nil
      }
    }
  }

  // MARK: - Writes

  func tap(
    _ query: FBAccessibilityElementQuery,
    options: FBTapOptions
  ) async throws {
    // A hold is a property of a synthesized touch, and this backend does not synthesize one — the AX
    // runtime's press is instantaneous and has nowhere to put a duration. Rejected rather than dropped:
    // a long-press that silently becomes a tap is a test that passes for the wrong reason.
    guard options.duration == nil else {
      throw FBUIAutomationError.operationUnsupported(backend: backend, operation: "A tap with a hold duration")
    }
    let target = try await writeTarget(for: query, operation: "A tap", callerAssertion: options.assertion)
    try await write(.perform(.press), to: target, query: query)
  }

  func setValue(_ value: String, for query: FBAccessibilityElementQuery) async throws {
    let target = try await writeTarget(for: query, operation: "Setting a value", callerAssertion: nil)
    try await write(.setValue(value), to: target, query: query)
  }

  func scroll(_ query: FBAccessibilityElementQuery, direction: FBAccessibilityScrollDirection) async throws {
    let target = try await writeTarget(for: query, operation: "Scroll", callerAssertion: nil)
    try await write(.perform(Self.action(for: direction)), to: target, query: query)
  }

  /// The semantic action a scroll direction asks for. Total over the direction, so a direction added to
  /// the enum has to be given a meaning here rather than silently scrolling somewhere.
  private static func action(for direction: FBAccessibilityScrollDirection) -> FBAXWire.Action {
    switch direction {
    case .up: .scrollUp
    case .down: .scrollDown
    case .left: .scrollLeft
    case .right: .scrollRight
    case .visible: .scrollToVisible
    }
  }

  /// Sends the write and turns the guest's envelope into the verb's outcome.
  ///
  /// An empty point is a successful read of nothing, which for a write means the thing the caller aimed
  /// at was not there — so it is an error rather than a write that passed. Which error depends on what
  /// the caller named, not on what the guest was sent: a marker write reports that its element moved, the
  /// same as when the guest finds a *different* element under the point. Both are the screen changing
  /// between the read that resolved the marker and the write that acted on it, and reporting one of them
  /// against coordinates the caller never chose would make the pair look like different conditions.
  private func write(
    _ kind: FBAXBridgeWriteRequest.Kind,
    to target: FBAXWriteTarget,
    query: FBAccessibilityElementQuery
  ) async throws {
    try await translatingWriteErrors(query) {
      let response = try await transport.write(
        FBAXBridgeWriteRequest(
          kind: kind,
          x: Double(target.point.x),
          y: Double(target.point.y),
          pid: target.pid,
          assertion: target.assertion
        )
      )
      guard try FBAXTreeRead.writeLanded(fromResponse: response) else {
        throw self.emptyWriteTargetError(for: query, at: target.point)
      }
    }
  }

  /// The seam translation for a write: the two application-level failures, plus the refused assertion,
  /// which only a write can meet. The guest reports what it found under the point; naming the marker that
  /// sent the write there is the host's half, so the two are joined here.
  private func translatingWriteErrors(_ query: FBAccessibilityElementQuery, _ body: () async throws -> Void) async throws {
    do {
      try await translatingSeamErrors(body)
    } catch let FBAXBridgeError.assertionFailed(message) {
      guard case let .marker(value, key, _) = query else {
        throw FBAXBridgeError.assertionFailed(message)
      }
      throw FBUIAutomationError.elementMoved(backend: backend, key: key.rawValue, value: value)
    }
  }

  // MARK: - Geometry

  /// Filed with the writes because that is the company `FBUIAutomation` keeps it in, but it is a pure
  /// read: `AXFrame` is an attribute of the tree the other verbs already read, so it is served by the
  /// shared tree-reader path with no wire verb and no guest change.
  func frame(_ query: FBAccessibilityElementQuery) async throws -> CGRect {
    try await frameFromTree(query)
  }

  // MARK: - Frontmost anchor

  /// The screen-centre anchor (in points) for the in-guest frontmost hit-test. The same point the
  /// remote backend uses (`FBSimulatorRemoteAutomation.anchorPoint`), so the two agree on "frontmost".
  private func frontmostAnchor() -> (x: Double, y: Double) {
    let info = simulator.screenInfo
    return FBSimulatorRemoteAutomation.anchorPoint(
      widthPixels: info?.widthPixels ?? 828, heightPixels: info?.heightPixels ?? 1792, scale: info?.scale ?? 2
    )
  }

  /// Warns that the traversal could not answer keys the caller asked for, so a caller can tell "this read
  /// could not ask" from "the app set nothing". A synchronous witness satisfies the `async` requirement.
  func warnIfUnsatisfiable(_ keys: Set<FBAXKeys>, strategy: FBAXTraversalStrategy) {
    guard !keys.isEmpty else {
      return
    }
    _ = simulator.logger.log(
      "the \(strategy.rawValue) traversal cannot answer "
        + keys.map(\.rawValue).sorted().joined(separator: ", ")
        + " for every element; a missing value there may mean this read could not ask, not that the "
        + "element has none"
    )
  }

  /// Warns when a whole-tree read hit the depth or node bound, so a truncated tree is never passed off
  /// as complete. Called once per describe by the shared `describeTree`; the `wait` poll reads via
  /// `readRawTree` without describing, so it never warns per iteration. A synchronous witness satisfies
  /// the `async` protocol requirement.
  func warnIfTruncated(_ truncated: Bool) {
    guard truncated else { return }
    _ = simulator.logger.log("axbridge read hit the bound (maxDepth \(FBAXReadLimits.maxReadDepth), maxNodes \(FBAXReadLimits.maxReadNodes)); the returned tree is truncated and incomplete.")
  }

  func warnIfGeometrySuspect(_ frames: FBAccessibilityFrameSummary?) {
    guard let advice = FBAccessibilityGuidance.suspectGeometry(frames), let frames else { return }
    _ = simulator.logger.log("axbridge read reported \(frames.zeroFrame) of \(frames.total) elements with no frame. \(advice)")
  }
}

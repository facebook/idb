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
/// service — an in-simulator accessibility client with no test bundle.
///
/// Writes are semantic accessibility actions addressed by point: a one-shot guest cannot hold an
/// element handle across requests, so a `.marker` write resolves its point host-side and carries an
/// assertion the guest re-checks before acting, so a screen that moved does not receive the write.
///
// SAFETY: stored state is immutable. Persistent transport state is actor-isolated and the one-shot
// transport is a value type.
// patternlint-disable-next-line unchecked-sendable
final class FBAXBridgeUIAutomation: FBAXBridgeTreeReader, @unchecked Sendable {

  /// `true` asserts automation mode, `false` asserts it off, `nil` observes without touching the
  /// device. Without the mode UIKit collapses subtrees and can serve cached children describing a
  /// screen no longer displayed.
  let requestedAutomationMode: Bool?

  private let simulator: FBSimulator

  /// How this reader reaches the guest.
  let transport: any FBAXBridgeTransport

  /// The transport lifecycle this reader was vended for. Held only so `backend` reports the case the
  /// caller selected; the injected transport already encodes the behavioural difference.
  private let persistence: FBAXBridgePersistence

  /// How frontmost reads resolve the foreground app. Defaults to the authoritative `.windowServer`; a
  /// caller can select the positional `.centerPoint` or `.runningBoard`.
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

  /// Converts application-level bridge failures to the public UI automation errors.
  private func translatingBackendErrors<T>(_ body: () async throws -> T) async throws -> T {
    do {
      return try await body()
    } catch let FBAXBridgeError.applicationUnavailable(pid) {
      throw FBUIAutomationError.applicationUnavailable(backend: backend, pid: pid)
    } catch let FBAXBridgeError.applicationNotResponding(pid) {
      throw FBUIAutomationError.applicationNotResponding(backend: backend, pid: pid)
    }
  }

  /// Assembles what both sides measured; the phases come off the envelope `FBAXTreeRead` already parsed.
  private static func timings(
    response: Data, sent: CFAbsoluteTime, returned: CFAbsoluteTime, read: FBAXTreeRead
  ) -> FBAXReadTimings {
    let decoded = CFAbsoluteTimeGetCurrent()
    let phases = read.phases
    return FBAXReadTimings(
      roundTrip: returned - sent,
      decode: decoded - returned,
      traverse: phases.traverse,
      machRoundTrips: phases.machRoundTrips,
      responseBytes: Int64(response.count)
    )
  }

  /// A single fetch that asks for reachability hit-tests every node and times out rather than
  /// answering, so those keys force the per-node walk.
  static func autoTraversal(for options: FBAccessibilityRequestOptions) -> FBAXTraversal {
    guard options.serializationKeys.isDisjoint(with: FBAXKeys.reachabilityKeys) else {
      return .viewHierarchy
    }
    return .singleFetch
  }

  /// `.application` reads the named pid; every other query is one fused guest call that resolves the
  /// frontmost app at the screen-centre anchor and reads its tree. `.point` goes through `hitTest`.
  func readRawTree(
    for query: FBAccessibilityElementQuery,
    attributes: [String]?,
    explainUnreachable: Bool,
    traversal: FBAXTraversal
  ) async throws -> FBAXTreeRead {
    try await translatingBackendErrors {
      if case let .application(pid) = query {
        let options = FBAXBridgeReadRequest(
          maxDepth: FBAXReadLimits.maxReadDepth,
          maxNodes: FBAXReadLimits.maxReadNodes,
          attributes: attributes,
          explainUnreachable: explainUnreachable,
          traversal: traversal,
          automationMode: requestedAutomationMode
        )
        let sent = CFAbsoluteTimeGetCurrent()
        let response = try await transport.send(.read(pid: pid, options: options))
        let returned = CFAbsoluteTimeGetCurrent()
        var read = try FBAXTreeRead(wholeTreeResponse: response, pid: pid)
        read.timings = Self.timings(response: response, sent: sent, returned: returned, read: read)
        return read
      }
      let anchor = frontmostAnchor()
      let options = FBAXBridgeReadRequest(
        maxDepth: FBAXReadLimits.maxReadDepth,
        maxNodes: FBAXReadLimits.maxReadNodes,
        attributes: attributes,
        explainUnreachable: explainUnreachable,
        traversal: traversal,
        automationMode: requestedAutomationMode
      )
      let sent = CFAbsoluteTimeGetCurrent()
      let response = try await transport.send(
        .readFrontmost(x: anchor.x, y: anchor.y, method: frontmostMethod, options: options)
      )
      let returned = CFAbsoluteTimeGetCurrent()
      var read = try FBAXTreeRead(frontmostResponse: response, method: frontmostMethod)
      read.timings = Self.timings(response: response, sent: sent, returned: returned, read: read)
      return read
    }
  }

  func hitTest(
    at point: CGPoint,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse? {
    try await translatingBackendErrors {
      let response = try await transport.send(
        .hitTest(
          x: Double(point.x), y: Double(point.y),
          attributes: FBAXWire.Node.fetchList(for: options.serializationKeys))
      )
      guard let hit = try FBAXTreeRead(hitTestResponse: response) else {
        return nil
      }
      let element = FBAXTreeWalk.buildPlatformElementTree(from: hit.tree, pid: hit.pid)
      var formatted = FBAXNodeSerializer.formattedDescription(
        ofElement: element, token: "", nestedFormat: options.nestedFormat, keys: options.serializationKeys, collector: nil
      )
      // The hit element is exempt from the filter; its descendants are not.
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
      // Re-read frontmost each poll so an app that launches mid-wait is picked up.
      do {
        // Raw read (not `describeTree`) so truncation is not warned per poll. `.viewHierarchy` because the
        // single fetch is unmeasured on a transitioning screen.
        let read = try await self.readRawTree(for: .frontmost, attributes: nil, explainUnreachable: false, traversal: .viewHierarchy)
        let elements = FBAXTreeWalk.describeAllElements(
          fromTree: read.tree, keys: FBAXKeys.defaultSet.union([key.serializationKey]), nestedFormat: false, pid: read.pid
        )
        return FBAXTreeWalk.matchingElement(inElements: elements, markerValue: markerValue, key: key) != nil ? true : nil
      } catch let error as FBAXBridgeError {
        guard error.isTransientDuringMarkerWait else {
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
    // The AX runtime's press is instantaneous with nowhere to put a hold; reject `duration` rather
    // than silently downgrading a long-press to a tap.
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

  /// Synthesized over HID: a drag is a touch path, not an action on a single element, so the guest has
  /// no verb for it.
  func drag(
    from source: FBAccessibilityElementQuery,
    to destination: FBAccessibilityElementQuery,
    options: FBDragOptions
  ) async throws {
    let start = try await writeTarget(for: source, operation: FBDragEndpoint.operation, callerAssertion: nil).point
    let end = try await writeTarget(for: destination, operation: FBDragEndpoint.operation, callerAssertion: nil).point
    try await simulator.sendHIDGesture(
      .drag(
        Double(start.x), yStart: Double(start.y), xEnd: Double(end.x), yEnd: Double(end.y),
        delta: options.delta, pressDuration: options.pressDuration, duration: options.duration,
        releaseDuration: options.releaseDuration
      )
    )
  }

  /// The semantic action a scroll direction asks for.
  private static func action(for direction: FBAccessibilityScrollDirection) -> FBAXWire.Action {
    switch direction {
    case .up: .scrollUp
    case .down: .scrollDown
    case .left: .scrollLeft
    case .right: .scrollRight
    case .visible: .scrollToVisible
    }
  }

  /// A write that landed on nothing is an error, not a success; see `emptyWriteTargetError`.
  private func write(
    _ kind: FBAXBridgeWriteRequest.Kind,
    to target: FBAXWriteTarget,
    query: FBAccessibilityElementQuery
  ) async throws {
    try await translatingWriteErrors(query) {
      let response = try await transport.send(
        .write(
          FBAXBridgeWriteRequest(
            kind: kind,
            x: Double(target.point.x),
            y: Double(target.point.y),
            pid: target.pid,
            assertion: target.assertion
          )
        )
      )
      guard try FBAXTreeRead.writeLanded(fromResponse: response) else {
        throw self.emptyWriteTargetError(for: query, at: target.point)
      }
    }
  }

  /// Adds the refused-assertion case, which only a write can meet, to the shared backend-error
  /// translation; the guest cannot know which marker sent the write.
  private func translatingWriteErrors(_ query: FBAccessibilityElementQuery, _ body: () async throws -> Void) async throws {
    do {
      try await translatingBackendErrors(body)
    } catch let FBAXBridgeError.assertionFailed(message) {
      guard case let .marker(value, key, _, _) = query else {
        throw FBAXBridgeError.assertionFailed(message)
      }
      throw FBUIAutomationError.elementMoved(backend: backend, key: key.rawValue, value: value)
    }
  }

  // MARK: - Geometry

  func frame(_ query: FBAccessibilityElementQuery) async throws -> CGRect {
    try await frameFromTree(query)
  }

  // MARK: - Frontmost anchor

  /// The screen-centre anchor, in points, for the in-guest frontmost hit-test.
  private func frontmostAnchor() -> (x: Double, y: Double) {
    let info = simulator.screenInfo
    return Self.anchorPoint(
      widthPixels: info?.widthPixels ?? 828, heightPixels: info?.heightPixels ?? 1792, scale: info?.scale ?? 2
    )
  }

  static func anchorPoint(widthPixels: UInt, heightPixels: UInt, scale: Float) -> (x: Double, y: Double) {
    let pointsPerPixel = scale > 0 ? Double(scale) : 1
    return (Double(widthPixels) / pointsPerPixel / 2, Double(heightPixels) / pointsPerPixel / 2)
  }

  func warnIfUnsatisfiable(_ keys: Set<FBAXKeys>, traversal: FBAXTraversal) {
    guard !keys.isEmpty else {
      return
    }
    _ = simulator.logger.log(
      "The \(traversal.rawValue) traversal cannot fetch "
        + keys.map(\.rawValue).sorted().joined(separator: ", ")
        + " for every element; a missing value may mean the attribute was unfetchable, not unset"
    )
  }

  func warnIfTruncated(_ truncated: Bool) {
    guard truncated else { return }
    _ = simulator.logger.log("axbridge read hit the bound (maxDepth \(FBAXReadLimits.maxReadDepth), maxNodes \(FBAXReadLimits.maxReadNodes)); the returned tree is truncated and incomplete.")
  }

  func profile(
    for read: FBAXTreeRead, elementCount: Int, serializeDuration: CFAbsoluteTime,
    traversal: FBAXTraversal
  ) -> FBAccessibilityProfile? {
    guard let timings = read.timings else {
      return nil
    }
    return .guestBridge(
      FBAXBridgeProfile(
        elementCount: Int64(elementCount),
        totalDuration: timings.roundTrip + timings.decode + serializeDuration,
        acquireDuration: timings.residual,
        readDuration: timings.traverse ?? 0,
        serializeDuration: serializeDuration,
        traversal: traversal,
        machRoundTrips: timings.machRoundTrips,
        hostDecodeDuration: timings.decode,
        responseBytes: timings.responseBytes
      ))
  }

  func warnIfReachabilityAcrossTree(_ keys: Set<FBAXKeys>) {
    guard keys.contains(.interactable) || keys.contains(.occludedBy) else { return }
    _ = simulator.logger.log(FBAccessibilityGuidance.reachabilityAcrossTree)
  }

  func warnIfMostElementsUnframed(_ frames: FBAccessibilityFrameSummary?) {
    guard let advice = FBAccessibilityGuidance.zeroFrameAdvice(frames), let frames else { return }
    _ = simulator.logger.log("axbridge read reported \(frames.zeroFrame) of \(frames.total) elements with no frame. \(advice)")
  }
}

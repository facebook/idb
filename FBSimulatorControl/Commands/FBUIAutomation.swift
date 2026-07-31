/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

/// Selects the backend a UI-automation element operation runs against.
public enum FBUIAutomationBackend: Sendable {
  /// The legacy CoreSimulator accessibility-translation path.
  case accessibility
  /// The bundle-free guest `testmanagerd` remote-automation channel (iOS 27+).
  case remoteAutomation
  /// The bundle-free guest AX-C reader: the `SimulatorFrameworkBridge` `accessibility` service spawned
  /// in the simulator. XCUI-grade like `.remoteAutomation`, light like `.accessibility`.
  case axBridge
  /// As `.axBridge`, but over a persistent (memoized) guest `serve` process reused across reads —
  /// ~30x faster warm, for long-lived host processes doing repeated reads.
  case axBridgePersistent
}

/// The converged UI-automation surface: element reads and element-targeted
/// actions, expressed once against an `FBAccessibilityElementQuery` target and run by the selected
/// backend. `FBSimulator.uiAutomation(backend:)` vends the backend that implements it.
///
/// Consumers (sime2e, the idb companion) map their own flag/enum to an `FBUIAutomationBackend`, build
/// an `FBAccessibilityElementQuery`, and call one verb — rather than re-implementing per-backend
/// dispatch, the pid-probe anchor, or the keys default themselves. Each backend already funnels into
/// the shared serializer/schema, so the response is identical in shape across backends.
public protocol FBUIAutomation: Sendable {

  /// Reads the element(s) named by `query` and serializes them to the shared accessibility schema.
  /// `.point`/`.marker` yield a single element; `.frontmost` yields the whole tree.
  func describe(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse

  /// Reads the element at `point` — a targeted hit-test — serialized to the shared schema, or `nil`
  /// when no element sits at the point. Unlike `describe(.point:)`, which throws for an empty point,
  /// `hitTest` returns `nil` so a caller (e.g. a streaming hit-test around a tap) can tell empty space
  /// from a reader failure, which still throws.
  func hitTest(
    at point: CGPoint,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse?

  /// Taps the element named by `query`. `.point` taps the coordinate; `.marker` finds the element and
  /// taps its centre. `expectedValue`, when given, asserts the element's value for `expectedKey`
  /// before tapping — accessibility only; ignored over remote automation. `.frontmost` taps the
  /// frontmost element over accessibility but is rejected over remote automation.
  func tap(
    _ query: FBAccessibilityElementQuery,
    expectedValue: String?,
    expectedKey: FBAXSearchableKey
  ) async throws

  /// Sets `value` on the element named by `query`. `.point`/`.marker` targets only.
  func setValue(
    _ value: String,
    for query: FBAccessibilityElementQuery
  ) async throws

  /// Polls until the element named by a `.marker` query appears, or throws when `timeout` elapses.
  /// `.point`/`.frontmost` are not waitable.
  func wait(
    _ query: FBAccessibilityElementQuery,
    timeout: TimeInterval,
    pollInterval: TimeInterval
  ) async throws

  /// Scrolls the element named by `query` in `direction`. Accessibility only for now; the remote
  /// backend rejects it with a clear error until remote scroll is implemented.
  func scroll(
    _ query: FBAccessibilityElementQuery,
    direction: FBAccessibilityScrollDirection
  ) async throws

  /// The frame (in screen points) of the element named by `query`. A geometry-only read for callers
  /// that need an element's position/size — e.g. to draw an overlay or resolve a pid — without a full
  /// serialize. Accessibility only for now; the remote backend rejects it with a clear error.
  func frame(_ query: FBAccessibilityElementQuery) async throws -> CGRect
}

public extension FBUIAutomation {

  /// Taps the element named by `query` with no value assertion.
  func tap(_ query: FBAccessibilityElementQuery) async throws {
    try await tap(query, expectedValue: nil, expectedKey: .label)
  }

  /// `describe`, serialized to canonical sorted-keys JSON — the form CLI front-ends emit.
  func describeJSON(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> Data {
    try await describe(query, options: options).sortedKeysJSON()
  }

  /// `hitTest`, serialized to canonical sorted-keys JSON, or `nil` when the point is empty — the form
  /// CLI front-ends emit for a targeted read.
  func hitTestJSON(
    at point: CGPoint,
    options: FBAccessibilityRequestOptions
  ) async throws -> Data? {
    try await hitTest(at: point, options: options)?.sortedKeysJSON()
  }

  /// Hit-tests `point`, then taps it via `hid`, returning the element that was under the point before
  /// the tap (or `nil` when the point was empty). The hit-test runs first, so the returned element is
  /// what the touch lands on; the tap is then sent whether or not an element was found. A reader
  /// failure throws — and the tap is not sent — so a caller can tell empty space from a broken reader.
  /// This is the composition primitive behind a streaming "tap and learn what you hit" server: it
  /// pairs a read backend (`self`) with a HID sender, owning only the ordering and tap-regardless policy.
  func tapAndHitTest(
    at point: CGPoint,
    options: FBAccessibilityRequestOptions,
    hid: FBSimulatorHID,
    logger: FBControlCoreLogger
  ) async throws -> FBAccessibilityElementsResponse? {
    let element = try await hitTest(at: point, options: options)
    try await hid.send(event: .tapAt(x: Double(point.x), y: Double(point.y)), logger: logger)
    return element
  }

  /// `tapAndHitTest`, serialized to canonical sorted-keys JSON, or `nil` when the point was empty.
  func tapAndHitTestJSON(
    at point: CGPoint,
    options: FBAccessibilityRequestOptions,
    hid: FBSimulatorHID,
    logger: FBControlCoreLogger
  ) async throws -> Data? {
    try await tapAndHitTest(at: point, options: options, hid: hid, logger: logger)?.sortedKeysJSON()
  }
}

private extension FBAccessibilityElementsResponse {
  /// The canonical sorted-keys JSON encoding every CLI front-end emits — one definition so the byte
  /// form can't drift between the describe, hit-test, and tap-and-hit-test paths.
  func sortedKeysJSON() throws -> Data {
    try JSONSerialization.data(withJSONObject: asDictionary(), options: .sortedKeys)
  }
}

public extension FBSimulator {

  /// The converged UI-automation surface for `backend` — element reads and element-targeted actions
  /// over a single query-shaped API. Each call returns a fresh reader that **owns its own warm
  /// resource**: `.remoteAutomation` owns a `testmanagerd` DTX session, `.axBridgePersistent` owns a
  /// guest `serve` process. Hold the returned instance to reuse its warm resource across operations;
  /// drop it to tear the resource down. `.accessibility` and `.axBridge` are stateless — they hold no
  /// warm resource, so reconstructing them per call is free.
  func uiAutomation(backend: FBUIAutomationBackend) throws -> any FBUIAutomation {
    switch backend {
    case .accessibility:
      return FBAccessibilityUIAutomation(operations: self)
    case .remoteAutomation:
      return try remoteAutomation()
    case .axBridge:
      return FBAXBridgeUIAutomation(simulator: self, transport: FBAXBridgeOneshotTransport(simulator: self))
    case .axBridgePersistent:
      return FBAXBridgeUIAutomation(simulator: self, transport: FBAXBridgePersistentTransport(simulator: self))
    }
  }
}

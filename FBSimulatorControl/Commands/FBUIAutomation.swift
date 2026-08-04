/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

/// The guest-transport lifecycle for the `.axBridge` backend: a fresh spawn per read, or a memoized
/// process reused across reads. It applies only to the axbridge backend, so it rides on that case as a
/// payload rather than existing as a backend of its own.
public enum FBAXBridgePersistence: Sendable, Equatable {
  /// A fresh guest spawn per read. Stateless and free to reconstruct per call — for a single one-shot
  /// read.
  case oneShot
  /// A persistent (memoized) guest `serve` process reused across reads — ~30x faster warm, for
  /// long-lived host processes doing repeated reads.
  case persistent
}

/// Selects the backend a UI-automation element operation runs against.
public enum FBUIAutomationBackend: Sendable, Equatable {
  /// The legacy CoreSimulator accessibility-translation path.
  case accessibility
  /// The bundle-free guest `testmanagerd` remote-automation channel (iOS 27+).
  case remoteAutomation
  /// The bundle-free guest AX-C reader: the `SimulatorFrameworkBridge` `accessibility` service spawned
  /// in the simulator. XCUI-grade like `.remoteAutomation`, light like `.accessibility`. `persistence`
  /// picks a fresh spawn per read or a reused `serve` process; `frontmostMethod` is how it resolves the
  /// foreground app. Both apply only to this backend, so they are payloads of the case rather than
  /// parameters every backend would have to ignore.
  case axBridge(persistence: FBAXBridgePersistence, frontmostMethod: FBAXBridgeFrontmostMethod)
}

/// Options for a `tap`: an optional hold duration and an optional pre-tap value assertion. Both default
/// off, so `FBTapOptions()` is an instantaneous, unconditional tap and `tap(_ query)` covers the common
/// case without constructing one.
public struct FBTapOptions: Sendable, Equatable {

  /// A pre-tap value assertion: read `key` on the resolved element and tap only if it equals `value`,
  /// else throw `FBUIAutomationError.valueMismatch`. Accessibility-only — only that backend can
  /// read-and-assert atomically; the remote backend rejects a non-nil assertion rather than tap with it
  /// silently dropped.
  public struct Assertion: Sendable, Equatable {
    public var key: FBAXSearchableKey
    public var value: String

    public init(key: FBAXSearchableKey, value: String) {
      self.key = key
      self.value = value
    }
  }

  /// The hold duration — a long-press. `nil` is an instantaneous tap. Honoured by the coordinate
  /// (HID-delivered) backends; the accessibility backend performs an instantaneous AXPress and ignores
  /// it.
  public var duration: TimeInterval?
  /// The pre-tap value assertion, or `nil` to tap unconditionally. See `Assertion`.
  public var assertion: Assertion?

  public init(duration: TimeInterval? = nil, assertion: Assertion? = nil) {
    self.duration = duration
    self.assertion = assertion
  }
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
  /// taps its centre. `options.assertion`, when given, asserts the element's value for its key before
  /// tapping — accessibility only; rejected (not silently dropped) over remote automation.
  /// `options.duration`, when given, holds the tap as a long-press on the coordinate backends; the
  /// accessibility backend performs an instantaneous press and ignores it. `.frontmost` taps the
  /// frontmost element over accessibility but is rejected over remote automation.
  func tap(
    _ query: FBAccessibilityElementQuery,
    options: FBTapOptions
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

  /// Taps the element named by `query` with no hold duration and no value assertion.
  func tap(_ query: FBAccessibilityElementQuery) async throws {
    try await tap(query, options: FBTapOptions())
  }
}

public extension FBAccessibilityElementsResponse {
  /// The canonical sorted-keys JSON encoding CLI front-ends emit for an element response — one
  /// definition, so the byte form can't drift between the describe and hit-test call sites that apply it.
  func sortedKeysJSON() throws -> Data {
    try JSONSerialization.data(withJSONObject: asDictionary(), options: .sortedKeys)
  }
}

public extension FBSimulator {

  /// The converged UI-automation surface for `backend` — element reads and element-targeted actions
  /// over a single query-shaped API. Each call returns a fresh reader that **owns its own warm
  /// resource**: `.remoteAutomation` owns a `testmanagerd` DTX session, `.axBridge(persistence:
  /// .persistent, …)` owns a guest `serve` process. Hold the returned instance to reuse its warm
  /// resource across operations; drop it to tear the resource down. `.accessibility` and
  /// `.axBridge(persistence: .oneShot, …)` are stateless — they hold no warm resource, so
  /// reconstructing them per call is free.
  ///
  /// The axbridge backend case carries the transport persistence and frontmost-resolution method it
  /// reads with, so those choices are expressed only where they apply rather than as arguments the
  /// other backends would ignore.
  func uiAutomation(backend: FBUIAutomationBackend) throws -> any FBUIAutomation {
    switch backend {
    case .accessibility:
      return FBAccessibilityUIAutomation(operations: self)
    case .remoteAutomation:
      return try remoteAutomation()
    case let .axBridge(persistence, frontmostMethod):
      let transport: any FBAXBridgeTransport =
        switch persistence {
        case .oneShot: FBAXBridgeOneshotTransport(simulator: self)
        case .persistent: FBAXBridgePersistentTransport(simulator: self)
        }
      return FBAXBridgeUIAutomation(
        simulator: self, transport: transport, persistence: persistence, frontmostMethod: frontmostMethod
      )
    }
  }
}

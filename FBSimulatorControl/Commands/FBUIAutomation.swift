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
  /// foreground app; `automationMode` is what the read asks the device's accessibility automation mode
  /// to be. All three apply only to this backend, so they are payloads of the case rather than
  /// parameters every backend would have to ignore.
  ///
  /// `automationMode` is tri-state for the reason the guest is: `true` asserts the mode, `false` asserts
  /// it off, and `nil` observes without touching the device. `false` is not a synonym for `nil` — it is
  /// what reads the tree as it would have been read before this mode was asserted, which is what
  /// reproducing the child-cache fault and measuring the mode's cost both need.
  case axBridge(
    persistence: FBAXBridgePersistence,
    frontmostMethod: FBAXBridgeFrontmostMethod,
    automationMode: Bool?
  )
}

public extension FBUIAutomationBackend {
  /// How this backend names itself — in the `complete` output document, and to any consumer selecting
  /// a backend by name. The persistence of the axbridge transport is part of the name because it is
  /// what a caller chose between, and it is the difference a read's timing profile reflects.
  var name: FBUIAutomationBackendName {
    switch self {
    case .accessibility:
      return .ax
    case .remoteAutomation:
      return .testmanagerd
    case let .axBridge(persistence, _, _):
      switch persistence {
      case .oneShot:
        return .axBridge
      case .persistent:
        return .axBridgePersistent
      }
    }
  }

  /// The backend a name selects — the inverse of `name`, kept beside it so the two directions form one
  /// bijection in one place; the round-trip is pinned over every case, so a new backend cannot be added
  /// without teaching both directions. `frontmostMethod` and `automationMode` are carried into the
  /// axbridge cases, the only ones they apply to; the other backends ignore them.
  ///
  /// `automationMode` defaults to asserting the mode, which is what selecting the axbridge lane by name
  /// means today. A caller that wants the pre-assertion behaviour — reproducing the child-cache fault,
  /// or measuring what the mode costs — passes `false` explicitly rather than getting it by omission.
  init(
    _ name: FBUIAutomationBackendName,
    frontmostMethod: FBAXBridgeFrontmostMethod = .windowServer,
    automationMode: Bool? = true
  ) {
    switch name {
    case .ax:
      self = .accessibility
    case .testmanagerd:
      self = .remoteAutomation
    case .axBridge:
      self = .axBridge(persistence: .oneShot, frontmostMethod: frontmostMethod, automationMode: automationMode)
    case .axBridgePersistent:
      self = .axBridge(
        persistence: .persistent, frontmostMethod: frontmostMethod, automationMode: automationMode)
    }
  }
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
  /// The response encoded in `format` — the one definition of how a read reaches a caller, so the byte
  /// form cannot drift between the describe and hit-test call sites that apply it.
  ///
  /// `default` and `nested` differ only in the elements the serializer already produced, so both emit
  /// the legacy envelope; `complete` emits the consolidated document. There is deliberately no second
  /// renderer beside this one: two encoders is how the formats would come to disagree about anything
  /// they are meant to share.
  ///
  /// Both formats render the same typed elements; they differ in which spelling they use, how much of
  /// the read they report, and — deliberately — which writer produces the bytes.
  ///
  /// `complete` is new, so it is encoded from its `Encodable` model. The legacy formats are written by
  /// `JSONSerialization`, because their exact byte form is part of a contract consumers already parse
  /// and the two writers disagree on non-integral doubles: `JSONSerialization` emits 17 significant
  /// digits where `JSONEncoder` emits the shortest round-tripping form. A sub-point frame edge is enough
  /// to diverge.
  func formattedOutputJSON(format: FBAccessibilityOutputFormat) throws -> Data {
    switch format {
    case .default, .nested:
      return try JSONSerialization.data(
        withJSONObject: ["elements": elements.legacyFoundationObject], options: .sortedKeys
      )
    case .complete:
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      return try encoder.encode(document)
    }
  }

  /// The encoding of a hit-test that found nothing — a successful empty result, distinct from a failed
  /// read. `default` and `nested` emit `{"elements":null}`; `complete` emits the ordinary document with
  /// no elements, so a consumer parses one shape whether or not the point was occupied.
  static func emptyOutputJSON(
    format: FBAccessibilityOutputFormat,
    backend: FBUIAutomationBackend,
    target: FBAccessibilityTargetDescriptor
  ) throws -> Data {
    let response = FBAccessibilityElementsResponse(
      elements: .empty, backend: backend.name, target: target
    )
    return try response.formattedOutputJSON(format: format)
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
    case let .axBridge(persistence, frontmostMethod, automationMode):
      let transport: any FBAXBridgeTransport =
        switch persistence {
        case .oneShot: FBAXBridgeOneshotTransport(simulator: self)
        case .persistent: FBAXBridgePersistentTransport(simulator: self)
        }
      return FBAXBridgeUIAutomation(
        simulator: self, transport: transport, persistence: persistence, frontmostMethod: frontmostMethod,
        automationMode: automationMode
      )
    }
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

/// Which guest a `.axBridge` read runs against: a fresh spawn of its own, the simulator's shared one,
/// or a private one held for the caller's lifetime. It applies only to the axbridge backend, so it
/// rides on that case as a payload rather than existing as a backend of its own.
public enum FBAXBridgePersistence: Sendable, Hashable {
  /// A fresh guest spawn per read. Stateless and free to reconstruct per call — for a single one-shot
  /// read.
  case oneShot
  /// A guest on the simulator's well-known socket, shared with any other process reading the same
  /// target. Discoverable, so a read can adopt one somebody else already warmed, and held no longer than
  /// a round trip so it is never taken out from under anyone.
  case shared
  /// A guest of the caller's own, on a socket whose name nobody else knows. Never discovered and never
  /// shared, so the caller may hold it for as long as it likes without denying anyone. For a process
  /// that owns the simulator for its lifetime.
  case exclusive
}

/// Selects the backend a UI-automation element operation runs against.
public enum FBUIAutomationBackend: Sendable, Equatable {
  /// The legacy CoreSimulator accessibility-translation path.
  case accessibility
  /// The bundle-free guest AX-C reader: the `SimulatorFrameworkBridge` `accessibility` service spawned
  /// in the simulator. `persistence` picks which guest the read runs against; `frontmostMethod` is how
  /// it resolves the foreground app; `automationMode` is what the read asks the device's accessibility
  /// automation mode to be.
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
  /// The backend name reported in the `complete` output document.
  var name: FBUIAutomationBackendName {
    switch self {
    case .accessibility:
      return .ax
    case let .axBridge(persistence, _, _):
      switch persistence {
      case .oneShot:
        return .axBridgeOneShot
      case .shared:
        return .axBridgePersistent
      case .exclusive:
        return .axBridgeExclusive
      }
    }
  }

  /// Builds the resolved backend represented by `name`.
  ///
  /// `automationMode` defaults to asserting the mode, which is what selecting the axbridge lane by name
  /// means today. A caller that wants the pre-assertion behaviour — reproducing the child-cache fault,
  /// or measuring what the mode costs — passes `false` explicitly rather than getting it by omission.
  init(
    resolvedName name: FBUIAutomationBackendName,
    frontmostMethod: FBAXBridgeFrontmostMethod = .windowServer,
    automationMode: Bool? = true
  ) {
    switch name {
    case .ax:
      self = .accessibility
    case .axBridgeOneShot:
      self = .axBridge(persistence: .oneShot, frontmostMethod: frontmostMethod, automationMode: automationMode)
    case .axBridgePersistent:
      self = .axBridge(
        persistence: .shared, frontmostMethod: frontmostMethod, automationMode: automationMode)
    case .axBridgeExclusive:
      self = .axBridge(
        persistence: .exclusive, frontmostMethod: frontmostMethod, automationMode: automationMode)
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

/// Options for a `drag`: the three phase durations and the sampling interval. Every value defaults to
/// what the gesture uses when a caller does not choose, so `FBDragOptions()` is the documented drag.
public struct FBDragOptions: Sendable, Equatable {

  /// The hold at the source before travel starts. This is the phase that makes the gesture a drag
  /// rather than a flick: iOS begins a drag session only once the press clears its long-press
  /// threshold.
  public var pressDuration: TimeInterval
  /// The travel time, spread evenly over the interpolated samples.
  public var duration: TimeInterval
  /// The hold at the destination before the touch lifts, so a drop target can settle.
  public var releaseDuration: TimeInterval
  /// The distance in screen points between interpolated samples.
  public var delta: Double

  public init(
    pressDuration: TimeInterval = 0.5,
    duration: TimeInterval = 0.5,
    releaseDuration: TimeInterval = 0.1,
    delta: Double = FBSimulatorHIDEvent.defaultSwipeDelta
  ) {
    self.pressDuration = pressDuration
    self.duration = duration
    self.releaseDuration = releaseDuration
    self.delta = delta
  }
}

/// What a drag endpoint names, once the queries that name no single element are refused. Shared by the
/// backends so a drag accepts the same endpoints whichever one runs it; they differ only in how a
/// marker becomes a point.
enum FBDragEndpoint: Equatable {
  case point(CGPoint)
  case marker(value: String, key: FBAXSearchableKey, depth: UInt)

  /// The verb named in the refusal.
  static let operation = "A drag endpoint"

  /// `.frontmost` and `.application` name a tree. Resolving one would drag from the middle of the
  /// application's own rectangle, which is somewhere the caller never named.
  init(_ query: FBAccessibilityElementQuery, backend: FBUIAutomationBackend) throws {
    switch query {
    case let .point(point):
      self = .point(point)
    case let .marker(value, key, depth, _):
      self = .marker(value: value, key: key, depth: depth)
    case .frontmost, .application:
      throw FBUIAutomationError.pointOrMarkerRequired(backend: backend, operation: Self.operation)
    }
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

  /// Presses `source`, drags to `destination`, and releases. `.point` endpoints are the coordinate
  /// itself; a `.marker` endpoint is the centre of the element it names. `.frontmost`/`.application`
  /// are not endpoints.
  ///
  /// Delivered as synthesized input on every backend, because no accessibility action expresses a
  /// drag. The backends differ only in how a marker endpoint is resolved and which transport carries
  /// the events.
  func drag(
    from source: FBAccessibilityElementQuery,
    to destination: FBAccessibilityElementQuery,
    options: FBDragOptions
  ) async throws
}

public extension FBUIAutomation {

  /// Taps the element named by `query` with no hold duration and no value assertion.
  func tap(_ query: FBAccessibilityElementQuery) async throws {
    try await tap(query, options: FBTapOptions())
  }

  /// Drags with the default phase durations and sampling interval.
  func drag(from source: FBAccessibilityElementQuery, to destination: FBAccessibilityElementQuery) async throws {
    try await drag(from: source, to: destination, options: FBDragOptions())
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
  /// over a single query-shaped API. Every call returns a fresh reader; the readers are cheap, and
  /// where a backend owns an expensive warm resource, who owns it differs by backend:
  ///
  /// - `.axBridge(persistence: .shared, …)` reads over a guest `serve` process on the simulator's
  ///   well-known socket, shared with every other process reading the same simulator. The connection is
  ///   released after each round trip so the next reader can have it, and no host ever ends the guest —
  ///   only its own idle timeout does.
  /// - `.axBridge(persistence: .exclusive, …)` reads over a guest of the caller's own, on a socket
  ///   nobody else can discover. Memoized per simulator and per persistence, and holds its connection
  ///   between reads. The guest was spawned with `--exit-on-disconnect`, so closing that connection is
  ///   what ends it — for a process that owns the simulator for its lifetime.
  /// - `.accessibility` and `.axBridge(persistence: .oneShot, …)` are stateless — they hold no warm
  ///   resource, so reconstructing them per call is free.
  ///
  /// The axbridge backend case carries the transport persistence and frontmost-resolution method it
  /// reads with, so those choices are expressed only where they apply rather than as arguments the
  /// other backends would ignore.
  func uiAutomation(backend: FBUIAutomationBackend) throws -> any FBUIAutomation {
    switch backend {
    case .accessibility:
      return FBAccessibilityUIAutomation(simulator: self)
    case let .axBridge(persistence, frontmostMethod, automationMode):
      let transport: any FBAXBridgeTransport =
        switch persistence {
        case .oneShot: FBAXBridgeOneshotTransport(simulator: self)
        case .shared: axBridgeTransport(.shared)
        case .exclusive: axBridgeTransport(.exclusive)
        }
      return FBAXBridgeUIAutomation(
        simulator: self, transport: transport, persistence: persistence, frontmostMethod: frontmostMethod,
        automationMode: automationMode
      )
    }
  }

  /// The socket-backed axbridge transport this target uses for `persistence`.
  ///
  /// Memoized rather than per-reader because the transport is what reaches the guest, and the spawn plus
  /// `initForRemoteAccess` behind it is the cost these lanes exist to avoid. `frontmostMethod` and
  /// `automationMode` belong to the reader, so readers differing in those share a transport.
  ///
  /// Keyed by persistence rather than by type alone, because a shared and an exclusive bridge are not
  /// interchangeable: handing a shared request the exclusive transport would read over a bridge nobody
  /// else can see, and handing an exclusive request the shared one would put the caller back to holding
  /// a bridge others are trying to use.
  private func axBridgeTransport(_ persistence: FBAXBridgePersistence) -> FBAXBridgePersistentTransport {
    commandCache.resolve { FBAXBridgeTransportsByPersistence() }
      .transport(for: persistence) { FBAXBridgePersistentTransport(simulator: self, persistence: persistence) }
  }

  /// Delivers one composed gesture over HID, which drains the transport once for the whole gesture
  /// rather than once per primitive event.
  internal func sendHIDGesture(_ event: FBSimulatorHIDEvent) async throws {
    try await connectToHID().send(event: event, logger: logger)
  }
}

/// One socket-backed transport per persistence, for one target.
///
/// `FBTargetCommandCache` keys its slots by type, and the two persistences need separate transports that
/// are the same type, so this holds them apart.
///
// SAFETY: `transports` is only read or written with `lock` held, so no mutable state is reachable from
// two threads at once.
// patternlint-disable-next-line unchecked-sendable
final class FBAXBridgeTransportsByPersistence: @unchecked Sendable {
  private let lock = NSLock()
  private var transports: [FBAXBridgePersistence: FBAXBridgePersistentTransport] = [:]

  func transport(
    for persistence: FBAXBridgePersistence,
    build: () -> FBAXBridgePersistentTransport
  ) -> FBAXBridgePersistentTransport {
    lock.lock()
    defer { lock.unlock() }
    if let existing = transports[persistence] {
      return existing
    }
    let created = build()
    transports[persistence] = created
    return created
  }
}

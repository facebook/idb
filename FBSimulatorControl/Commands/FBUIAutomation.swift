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
/// or a private one held for the caller's lifetime.
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
  /// The guest AX reader: the `SimulatorFrameworkBridge` `accessibility` service spawned in the
  /// simulator. `persistence` picks which guest; `frontmostMethod` is how it resolves the foreground
  /// app; `automationMode` is `true` to assert automation mode, `false` to assert it off, `nil` to
  /// leave the device untouched.
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
  /// else throw `FBUIAutomationError.valueMismatch`.
  public struct Assertion: Sendable, Equatable {
    public var key: FBAXSearchableKey
    public var value: String

    public init(key: FBAXSearchableKey, value: String) {
      self.key = key
      self.value = value
    }
  }

  /// Requests a long-press; a backend whose press is instantaneous rejects it rather than downgrading to
  /// a tap. `nil` is an instantaneous tap.
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

/// What a drag endpoint names, once the queries that name no single element are refused.
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

  /// Taps the element named by `query`. `.point` taps the coordinate; `.marker` taps the element's
  /// centre. `options.assertion` checks the element's value for its key before tapping.
  /// `options.duration` asks for a long-press; a backend whose press is instantaneous rejects it rather
  /// than downgrading to a tap.
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

  /// Scrolls the element named by `query` in `direction`.
  func scroll(
    _ query: FBAccessibilityElementQuery,
    direction: FBAccessibilityScrollDirection
  ) async throws

  /// The frame (in screen points) of the element named by `query`. A geometry-only read for callers
  /// that need an element's position or size without a full serialization.
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
  /// `default`/`nested` are written by `JSONSerialization` because their byte form is a contract
  /// consumers parse, and it differs from `JSONEncoder` on non-integral doubles (17 significant digits
  /// vs the shortest round-trip form). `complete` is encoded from its `Encodable` model.
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
  func uiAutomation(backend: FBUIAutomationBackend) throws -> any FBUIAutomation {
    switch backend {
    case .accessibility:
      return FBAccessibilityUIAutomation(simulator: self)
    case let .axBridge(persistence, frontmostMethod, automationMode):
      let transport: any FBAXBridgeTransport =
        switch persistence {
        case .oneShot: FBAXBridgeOneshotTransport(simulator: self)
        case .shared: axBridgeTransport(scope: .shared)
        case .exclusive: axBridgeTransport(scope: .exclusive)
        }
      return FBAXBridgeUIAutomation(
        simulator: self, transport: transport, persistence: persistence, frontmostMethod: frontmostMethod,
        automationMode: automationMode
      )
    }
  }

  /// Memoized per scope: the spawn plus `initForRemoteAccess` behind a transport is the cost the
  /// persistent modes exist to avoid. Shared and exclusive transports are never interchangeable.
  /// `frontmostMethod` and `automationMode` belong to the reader, so readers differing in those share
  /// a transport.
  private func axBridgeTransport(scope: FBAXBridgeServiceScope) -> FBAXBridgePersistentTransport {
    commandCache.resolve { FBAXBridgeTransportsByScope() }
      .transport(for: scope) { FBAXBridgePersistentTransport(simulator: self, scope: scope) }
  }

  /// Delivers one composed gesture over HID, which drains the transport once for the whole gesture
  /// rather than once per primitive event.
  internal func sendHIDGesture(_ event: FBSimulatorHIDEvent) async throws {
    try await connectToHID().send(event: event, logger: logger)
  }
}

/// One socket-backed transport per service scope, for one target.
///
/// `FBTargetCommandCache` keys its slots by type, and the two scopes need separate transports that
/// are the same type, so this holds them apart.
///
// SAFETY: `transports` is only read or written with `lock` held, so no mutable state is reachable from
// two threads at once.
// patternlint-disable-next-line unchecked-sendable
final class FBAXBridgeTransportsByScope: @unchecked Sendable {
  private let lock = NSLock()
  private var transports: [FBAXBridgeServiceScope: FBAXBridgePersistentTransport] = [:]

  func transport(
    for scope: FBAXBridgeServiceScope,
    build: () -> FBAXBridgePersistentTransport
  ) -> FBAXBridgePersistentTransport {
    lock.lock()
    defer { lock.unlock() }
    if let existing = transports[scope] {
      return existing
    }
    let created = build()
    transports[scope] = created
    return created
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Where a translator-backed read spent its time.
///
/// Disjoint from `FBAXBridgeProfile` because the backends measure different phases. Their common fields
/// use the same names so callers can compare backend performance without flattening the two models.
public struct FBAccessibilityProfilingData: Sendable, Equatable, Encodable {

  // MARK: The core, spelled identically in every backend's profile

  /// Elements in the serialized read.
  public let elementCount: Int64
  /// Wall time for the whole read: the number a caller waited.
  public let totalDuration: CFAbsoluteTime
  /// Getting into a position to read at all — the translation object, and the platform element made
  /// from it.
  public let acquireDuration: CFAbsoluteTime
  /// Pulling the tree out of the application. For this backend that is the walk's XPC wait: attributes are
  /// fetched one round trip at a time, and the waiting is the pulling.
  public let readDuration: CFAbsoluteTime
  /// Turning what was read into what the caller asked for — the walk's time less what it spent waiting.
  public let serializeDuration: CFAbsoluteTime

  // MARK: What only a translator-backed read has

  /// The number of attribute fetches made on accessibility elements. Each
  /// property access (accessibilityLabel, accessibilityFrame, etc.) counts as one.
  public let attributeFetchCount: Int64

  /// The number of XPC calls made to the simulator's accessibility service.
  public let xpcCallCount: Int64

  /// The time spent in performWithTranslator (getting the translation object). A component of
  /// `acquireDuration`.
  public let translationDuration: CFAbsoluteTime

  /// The time spent converting the translation object to a platform element. The other component of
  /// `acquireDuration`.
  public let elementConversionDuration: CFAbsoluteTime

  /// The total time spent in XPC calls, across the whole read. Larger than `readDuration` by whatever
  /// acquisition itself spent on XPC, which is reported there as wall time instead.
  public let totalXPCDuration: CFAbsoluteTime

  /// The set of keys that were fetched during serialization.
  public let fetchedKeys: Set<String>

  public init(
    elementCount: Int64,
    totalDuration: CFAbsoluteTime,
    acquireDuration: CFAbsoluteTime,
    readDuration: CFAbsoluteTime,
    serializeDuration: CFAbsoluteTime,
    attributeFetchCount: Int64,
    xpcCallCount: Int64,
    translationDuration: CFAbsoluteTime,
    elementConversionDuration: CFAbsoluteTime,
    totalXPCDuration: CFAbsoluteTime,
    fetchedKeys: Set<String>
  ) {
    self.elementCount = elementCount
    self.totalDuration = totalDuration
    self.acquireDuration = acquireDuration
    self.readDuration = readDuration
    self.serializeDuration = serializeDuration
    self.attributeFetchCount = attributeFetchCount
    self.xpcCallCount = xpcCallCount
    self.translationDuration = translationDuration
    self.elementConversionDuration = elementConversionDuration
    self.totalXPCDuration = totalXPCDuration
    self.fetchedKeys = fetchedKeys
  }

  enum CodingKeys: String, CodingKey {
    case elementCount = "element_count"
    case totalDurationMs = "total_duration_ms"
    case acquireDurationMs = "acquire_duration_ms"
    case readDurationMs = "read_duration_ms"
    case serializeDurationMs = "serialize_duration_ms"
    case attributeFetchCount = "attribute_fetch_count"
    case xpcCallCount = "xpc_call_count"
    case translationDurationMs = "translation_duration_ms"
    case elementConversionDurationMs = "element_conversion_duration_ms"
    case totalXpcDurationMs = "total_xpc_duration_ms"
  }

  /// `fetchedKeys` is a diagnostic, not part of the reported profile, so it is not encoded.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(elementCount, forKey: .elementCount)
    try container.encode(totalDuration * 1000, forKey: .totalDurationMs)
    try container.encode(acquireDuration * 1000, forKey: .acquireDurationMs)
    try container.encode(readDuration * 1000, forKey: .readDurationMs)
    try container.encode(serializeDuration * 1000, forKey: .serializeDurationMs)
    try container.encode(attributeFetchCount, forKey: .attributeFetchCount)
    try container.encode(xpcCallCount, forKey: .xpcCallCount)
    try container.encode(translationDuration * 1000, forKey: .translationDurationMs)
    try container.encode(elementConversionDuration * 1000, forKey: .elementConversionDurationMs)
    try container.encode(totalXPCDuration * 1000, forKey: .totalXpcDurationMs)
  }
}

extension FBAccessibilityProfilingData: CustomStringConvertible {
  public var description: String {
    String(
      format: "<FBAccessibilityProfilingData: elements=%lld, total=%.2fms, acquire=%.2fms, read=%.2fms, serialize=%.2fms>",
      elementCount,
      totalDuration * 1000,
      acquireDuration * 1000,
      readDuration * 1000,
      serializeDuration * 1000
    )
  }
}

/// A fullscreen modal / alert over the read target, carried on the SimulatorFrameworkBridge ->
/// FBSimulatorControl wire. Surfaced only by the `complete` format; the legacy envelope stays
/// byte-stable.
public struct FBAccessibilityModalInfo: Sendable, Equatable, Encodable {

  /// Who owns the modal: the system shell (SpringBoard — a system/permission alert) or the app itself
  /// (an in-app `UIAlertController`).
  public enum Kind: String, Sendable, Encodable {
    case system
    case app
  }

  public let kind: Kind

  /// The concrete accessibility element class of the alert, e.g. `SBAlertItemWindow` (system) or
  /// `_UIAlertControllerPhoneTVMacView` (UIKit alert).
  public let elementType: String

  /// The alert's title / primary label, when the guest could read one.
  public let label: String?

  public init(kind: Kind, elementType: String, label: String?) {
    self.kind = kind
    self.elementType = elementType
    self.label = label
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case elementType = "element_type"
    case label
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind, forKey: .kind)
    try container.encode(elementType, forKey: .elementType)
    try container.encode(label, forKey: .label)
  }
}

/// Response object containing accessibility elements and optional profiling data.
public struct FBAccessibilityElementsResponse: Sendable {

  /// The accessibility elements: an object (single element) or an array (flat/nested tree).
  public let elements: FBAccessibilityElementPayload

  /// Where the read spent its time, when the backend measured it. `.translator` and `.guestBridge`
  /// measure disjoint phases; `backend` says which to expect.
  public let profilingData: FBAccessibilityProfile?

  /// How much of the screen the read's element frames cover, or `nil` when coverage was not requested.
  public let coverage: FBAccessibilityCoverage?

  /// A fullscreen modal / alert over the read target, when detected. Emitted only by the `complete`
  /// document; the legacy envelope is byte-stable and must not gain it.
  public let modal: FBAccessibilityModalInfo?

  /// Whether the read's tree walk was cut short by a depth or node bound, so the elements are a
  /// partial view. Only the `complete` document surfaces this.
  public let truncated: Bool

  /// The bounds the element frames are relative to, when the read knows them.
  public let screen: FBAccessibilityScreenInfo?

  /// Which backend produced the read.
  public let backend: FBUIAutomationBackendName?

  /// What the read was asked for.
  public let target: FBAccessibilityTargetDescriptor?

  /// The device's accessibility automation mode for this read, when the backend reported it.
  public let automation: FBAccessibilityAutomationState?

  /// What narrowed the read and how much survived, for a read that could narrow. Nil for the
  /// single-element reads, which select an element rather than narrow a list.
  public let narrowing: FBAccessibilityNarrowing?

  public init(
    elements: FBAccessibilityElementPayload,
    profilingData: FBAccessibilityProfile? = nil,
    coverage: FBAccessibilityCoverage? = nil,
    modal: FBAccessibilityModalInfo? = nil,
    truncated: Bool = false,
    screen: FBAccessibilityScreenInfo? = nil,
    backend: FBUIAutomationBackendName? = nil,
    target: FBAccessibilityTargetDescriptor? = nil,
    automation: FBAccessibilityAutomationState? = nil,
    narrowing: FBAccessibilityNarrowing? = nil
  ) {
    self.elements = elements
    self.profilingData = profilingData
    self.coverage = coverage
    self.modal = modal
    self.truncated = truncated
    self.screen = screen
    self.backend = backend
    self.target = target
    self.automation = automation
    self.narrowing = narrowing
  }

  /// A copy carrying the read's provenance; a `nil` argument leaves the existing value in place.
  public func withProvenance(
    backend: FBUIAutomationBackendName? = nil,
    target: FBAccessibilityTargetDescriptor? = nil,
    screen: FBAccessibilityScreenInfo? = nil,
    truncated: Bool? = nil
  ) -> FBAccessibilityElementsResponse {
    FBAccessibilityElementsResponse(
      elements: elements,
      profilingData: profilingData,
      coverage: coverage,
      modal: modal,
      truncated: truncated ?? self.truncated,
      screen: screen ?? self.screen,
      backend: backend ?? self.backend,
      target: target ?? self.target,
      automation: automation,
      narrowing: narrowing
    )
  }

  /// A copy reporting what narrowed the read.
  public func withNarrowing(_ narrowing: FBAccessibilityNarrowing) -> FBAccessibilityElementsResponse {
    FBAccessibilityElementsResponse(
      elements: elements,
      profilingData: profilingData,
      coverage: coverage,
      modal: modal,
      truncated: truncated,
      screen: screen,
      backend: backend,
      target: target,
      automation: automation,
      narrowing: narrowing
    )
  }

  /// A copy whose screen bounds are replaced, including with `nil` when a read has no screen context.
  public func replacingScreen(_ screen: FBAccessibilityScreenInfo?) -> FBAccessibilityElementsResponse {
    FBAccessibilityElementsResponse(
      elements: elements,
      profilingData: profilingData,
      coverage: coverage,
      modal: modal,
      truncated: truncated,
      screen: screen,
      backend: backend,
      target: target,
      automation: automation,
      narrowing: narrowing
    )
  }

  /// The `complete` output format for this read.
  public var document: FBAccessibilityDocument {
    let reported = elements.elements.map { $0.reportingChildren() }
    return FBAccessibilityDocument(
      elements: reported,
      modal: modal,
      truncated: truncated,
      screen: screen,
      backend: backend,
      target: target,
      profile: profilingData,
      coverage: coverage,
      interaction: FBAccessibilityInteractionSummary(elements: reported),
      frames: FBAccessibilityFrameSummary(elements: reported),
      automation: automation,
      narrowing: narrowing
    )
  }

}

extension FBAccessibilityElementsResponse: CustomStringConvertible {
  public var description: String {
    "<FBAccessibilityElementsResponse: elements=\(Swift.type(of: elements)), profiling=\(String(describing: profilingData)), coverage=\(String(describing: coverage)), modal=\(String(describing: modal))>"
  }
}

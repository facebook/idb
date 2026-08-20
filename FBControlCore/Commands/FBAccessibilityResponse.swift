/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Profiling data collected during an accessibility operation. Provides
/// visibility into the performance characteristics of the AX subsystem.
public struct FBAccessibilityProfilingData: Sendable, Equatable, Encodable {

  /// The number of accessibility elements that were serialized.
  public let elementCount: Int64

  /// The number of attribute fetches made on accessibility elements. Each
  /// property access (accessibilityLabel, accessibilityFrame, etc.) counts as one.
  public let attributeFetchCount: Int64

  /// The number of XPC calls made to the simulator's accessibility service.
  public let xpcCallCount: Int64

  /// The time spent in performWithTranslator (getting the translation object).
  public let translationDuration: CFAbsoluteTime

  /// The time spent converting the translation object to a platform element.
  public let elementConversionDuration: CFAbsoluteTime

  /// The time spent serializing the accessibility tree.
  public let serializationDuration: CFAbsoluteTime

  /// The total time spent in XPC calls.
  public let totalXPCDuration: CFAbsoluteTime

  /// The set of keys that were fetched during serialization. Useful for tests
  /// to verify which attributes were actually accessed.
  public let fetchedKeys: Set<String>

  public init(
    elementCount: Int64,
    attributeFetchCount: Int64,
    xpcCallCount: Int64,
    translationDuration: CFAbsoluteTime,
    elementConversionDuration: CFAbsoluteTime,
    serializationDuration: CFAbsoluteTime,
    totalXPCDuration: CFAbsoluteTime,
    fetchedKeys: Set<String>
  ) {
    self.elementCount = elementCount
    self.attributeFetchCount = attributeFetchCount
    self.xpcCallCount = xpcCallCount
    self.translationDuration = translationDuration
    self.elementConversionDuration = elementConversionDuration
    self.serializationDuration = serializationDuration
    self.totalXPCDuration = totalXPCDuration
    self.fetchedKeys = fetchedKeys
  }

  enum CodingKeys: String, CodingKey {
    case elementCount = "element_count"
    case attributeFetchCount = "attribute_fetch_count"
    case xpcCallCount = "xpc_call_count"
    case translationDurationMs = "translation_duration_ms"
    case elementConversionDurationMs = "element_conversion_duration_ms"
    case serializationDurationMs = "serialization_duration_ms"
    case totalXpcDurationMs = "total_xpc_duration_ms"
  }

  /// Counts stay integers and durations are emitted in milliseconds. `fetchedKeys` is a test-facing
  /// diagnostic, not part of the reported profile, so it is not encoded.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(elementCount, forKey: .elementCount)
    try container.encode(attributeFetchCount, forKey: .attributeFetchCount)
    try container.encode(xpcCallCount, forKey: .xpcCallCount)
    try container.encode(translationDuration * 1000, forKey: .translationDurationMs)
    try container.encode(elementConversionDuration * 1000, forKey: .elementConversionDurationMs)
    try container.encode(serializationDuration * 1000, forKey: .serializationDurationMs)
    try container.encode(totalXPCDuration * 1000, forKey: .totalXpcDurationMs)
  }
}

extension FBAccessibilityProfilingData: CustomStringConvertible {
  public var description: String {
    String(
      format: "<FBAccessibilityProfilingData: elements=%lld, xpc_calls=%lld, translation=%.2fms, serialization=%.2fms>",
      elementCount,
      xpcCallCount,
      translationDuration * 1000,
      serializationDuration * 1000
    )
  }
}

/// Describes a fullscreen modal / alert present over the read target. Carried on the internal
/// SimulatorFrameworkBridge -> FBSimulatorControl wire to enrich the host's view of what is on screen.
///
/// Surfaced by the `complete` output format only — see `FBAccessibilityElementsResponse.modal`. It lets
/// a consumer detect and classify a modal semantically rather than inferring one from an element's
/// geometry or type, and it stays out of the legacy envelope so that output is byte-stable.
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

  /// `label` keeps its key with a `null` value when the guest could not read one, matching the
  /// document's fixed-key-set rule.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind, forKey: .kind)
    try container.encode(elementType, forKey: .elementType)
    try container.encode(label, forKey: .label)
  }
}

/// Response object containing accessibility elements and optional profiling data.
///
/// `elements` is a `Sendable` value type, so a response can cross concurrency domains (e.g. the
/// remote-automation actor) without an `@unchecked` conformance.
public struct FBAccessibilityElementsResponse: Sendable {

  /// The accessibility elements: an object (single element) or an array (flat/nested tree).
  public let elements: FBAccessibilityElementPayload

  /// Where the read spent its time, when the backend measured it.
  ///
  /// Typed per backend rather than shared: `.translator` and `.guestBridge` measure disjoint phases, and
  /// the document's `backend` already says which to expect.
  public let profilingData: FBAccessibilityProfile?

  /// How much of the screen the read's element frames cover, or `nil` when coverage was not requested.
  ///
  /// One value rather than a field per ratio: the reported and walked coverages are computed from the
  /// same pass over the same read, so a response can never hold one without the other.
  public let coverage: FBAccessibilityCoverage?

  /// A fullscreen modal / alert present over the read target, when one was detected. Emitted by the
  /// `complete` document and **deliberately absent from the legacy envelope**, whose bytes are frozen
  /// by the goldens.
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

  public init(
    elements: FBAccessibilityElementPayload,
    profilingData: FBAccessibilityProfile? = nil,
    coverage: FBAccessibilityCoverage? = nil,
    modal: FBAccessibilityModalInfo? = nil,
    truncated: Bool = false,
    screen: FBAccessibilityScreenInfo? = nil,
    backend: FBUIAutomationBackendName? = nil,
    target: FBAccessibilityTargetDescriptor? = nil,
    automation: FBAccessibilityAutomationState? = nil
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
  }

  /// A copy carrying the provenance of the read that produced it. The backend and the query are known
  /// at the read site rather than by the caller that asked for a format, so each backend stamps what it
  /// knows on its way out instead of every front-end having to describe the read it just made.
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
      automation: automation
    )
  }

  /// A copy that reports no screen bounds.
  ///
  /// `withProvenance` can only supply bounds, never withdraw them, because it defaults each field to
  /// what the response already carries. A read that resolved a single element needs the opposite: the
  /// serializer takes a read's bounds from the element it is handed, and for a single element that is
  /// the element's own frame, which describes the element rather than the screen. Reporting that would
  /// be worse than reporting nothing.
  public func withoutScreen() -> FBAccessibilityElementsResponse {
    FBAccessibilityElementsResponse(
      elements: elements,
      profilingData: profilingData,
      coverage: coverage,
      modal: modal,
      truncated: truncated,
      screen: nil,
      backend: backend,
      target: target,
      automation: automation
    )
  }

  /// The `complete` output format for this read.
  ///
  /// The document is a plain `Encodable` tree, so the emitted shape is fixed by the types rather than
  /// assembled as an untyped dictionary.
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
      // Derived from the elements rather than threaded through the read: it is a tally of what was just
      // serialized, so computing it anywhere else would only create a way for the two to disagree.
      interaction: FBAccessibilityInteractionSummary(elements: reported),
      frames: FBAccessibilityFrameSummary(elements: reported),
      automation: automation
    )
  }

}

extension FBAccessibilityElementsResponse: CustomStringConvertible {
  public var description: String {
    "<FBAccessibilityElementsResponse: elements=\(Swift.type(of: elements)), profiling=\(String(describing: profilingData)), coverage=\(String(describing: coverage)), modal=\(String(describing: modal))>"
  }
}

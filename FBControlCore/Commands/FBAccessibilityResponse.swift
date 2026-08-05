/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Profiling data collected during an accessibility operation. Provides
/// visibility into the performance characteristics of the AX subsystem.
public struct FBAccessibilityProfilingData: Sendable, Encodable {

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

  /// The profile as it appears in the legacy envelope, whose bytes are frozen by the goldens.
  func legacyDictionary() -> [String: NSNumber] {
    [
      "element_count": NSNumber(value: elementCount),
      "attribute_fetch_count": NSNumber(value: attributeFetchCount),
      "xpc_call_count": NSNumber(value: xpcCallCount),
      "translation_duration_ms": NSNumber(value: translationDuration * 1000),
      "element_conversion_duration_ms": NSNumber(value: elementConversionDuration * 1000),
      "serialization_duration_ms": NSNumber(value: serializationDuration * 1000),
      "total_xpc_duration_ms": NSNumber(value: totalXPCDuration * 1000),
    ]
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
/// `elements` is the serializer's JSON payload as a `Sendable` `FBJSONValue` — an object (single
/// element) or an array (flat/nested tree) — so a response can cross concurrency domains (e.g. the
/// remote-automation actor) without an `@unchecked` conformance.
public struct FBAccessibilityElementsResponse: Sendable {

  /// The accessibility elements: an object (single element) or an array (flat/nested tree).
  public let elements: FBJSONValue

  /// Profiling data collected during the operation, if profiling was enabled.
  public let profilingData: FBAccessibilityProfilingData?

  /// The proportion of the screen covered by accessibility element frames (0.0 - 1.0).
  /// Nil if coverage calculation was not requested. Low values suggest remote content.
  public let frameCoverage: Double?

  /// Additional coverage discovered via grid-based hit-testing for remote content.
  /// Nil if remote content discovery was not performed or found nothing.
  public let additionalFrameCoverage: Double?

  /// A fullscreen modal / alert present over the read target, when one was detected. Emitted by
  /// the `complete` document and **deliberately excluded from `asDictionary()`**, whose bytes are
  /// frozen by the goldens.
  public let modal: FBAccessibilityModalInfo?

  /// Whether the read's tree walk was cut short by a depth or node bound, so the elements are a
  /// partial view. Only the `complete` document surfaces this.
  public let truncated: Bool

  /// The bounds the element frames are relative to, when the read knows them.
  public let screen: FBAccessibilityScreenInfo?

  /// Which backend produced the read.
  public let backend: FBAccessibilityBackendName?

  /// What the read was asked for.
  public let target: FBAccessibilityTargetDescriptor?

  public init(
    elements: FBJSONValue,
    profilingData: FBAccessibilityProfilingData? = nil,
    frameCoverage: Double? = nil,
    additionalFrameCoverage: Double? = nil,
    modal: FBAccessibilityModalInfo? = nil,
    truncated: Bool = false,
    screen: FBAccessibilityScreenInfo? = nil,
    backend: FBAccessibilityBackendName? = nil,
    target: FBAccessibilityTargetDescriptor? = nil
  ) {
    self.elements = elements
    self.profilingData = profilingData
    self.frameCoverage = frameCoverage
    self.additionalFrameCoverage = additionalFrameCoverage
    self.modal = modal
    self.truncated = truncated
    self.screen = screen
    self.backend = backend
    self.target = target
  }

  /// A copy carrying the provenance of the read that produced it. The backend and the query are known
  /// at the read site rather than by the caller that asked for a format, so each backend stamps what it
  /// knows on its way out instead of every front-end having to describe the read it just made.
  public func withProvenance(
    backend: FBAccessibilityBackendName? = nil,
    target: FBAccessibilityTargetDescriptor? = nil,
    screen: FBAccessibilityScreenInfo? = nil,
    truncated: Bool? = nil
  ) -> FBAccessibilityElementsResponse {
    FBAccessibilityElementsResponse(
      elements: elements,
      profilingData: profilingData,
      frameCoverage: frameCoverage,
      additionalFrameCoverage: additionalFrameCoverage,
      modal: modal,
      truncated: truncated ?? self.truncated,
      screen: screen ?? self.screen,
      backend: backend ?? self.backend,
      target: target ?? self.target
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
      frameCoverage: frameCoverage,
      additionalFrameCoverage: additionalFrameCoverage,
      modal: modal,
      truncated: truncated,
      screen: nil,
      backend: backend,
      target: target
    )
  }

  /// A JSON-serializable dictionary with elements always embedded.
  /// Format: `{"elements": <elements>, "profile": <profile>, "coverage": <coverage>}`.
  /// `profile` and `coverage` are included only when the corresponding data is present.
  ///
  /// The signals the read also carries — `modal`, `truncated`, `screen`, `backend`, `target` — are
  /// intentionally **not** serialized here: this envelope's bytes are frozen by the goldens, and every
  /// one of them is surfaced by the `complete` document instead. Keep them out of this method.
  public func asDictionary() -> [String: Any] {
    var dict: [String: Any] = ["elements": elements.toFoundationObject()]
    if let profilingData {
      dict["profile"] = profilingData.legacyDictionary()
    }
    if let frameCoverage {
      var coverage: [String: Any] = ["frame": frameCoverage]
      if let additionalFrameCoverage {
        coverage["additional"] = additionalFrameCoverage
      }
      dict["coverage"] = coverage
    }
    return dict
  }

  /// The `complete` output format for this read.
  ///
  /// The document is a plain `Encodable` tree, so the emitted shape is fixed by the types rather than
  /// assembled as an untyped dictionary. The only mapping this does is turn the serializer's
  /// attribute-keyed nodes into typed elements.
  public var document: FBAccessibilityDocument {
    FBAccessibilityDocument(
      elements: Self.completeElements(from: elements),
      modal: modal,
      truncated: truncated,
      screen: screen,
      backend: backend,
      target: target,
      profile: profilingData,
      coverage: frameCoverage.map { FBAccessibilityCoverage(frame: $0, additional: additionalFrameCoverage) }
    )
  }

  /// The serialized nodes as typed elements: always an array, even for a single-element read.
  ///
  /// Mapping the already-serialized payload — rather than re-reading the elements under a second key
  /// vocabulary — keeps one attribute-read pass as the single source of every value, so the two
  /// schemas cannot disagree about what an element *is*, only about how it is spelled and typed.
  static func completeElements(from elements: FBJSONValue) -> [FBAccessibilityDocumentElement] {
    switch elements {
    case let .array(nodes):
      return nodes.compactMap(completeElement)
    case .object:
      return [completeElement(elements)].compactMap { $0 }
    case .null, .string, .bool, .int, .double:
      return []
    }
  }

  private static func completeElement(_ node: FBJSONValue) -> FBAccessibilityDocumentElement? {
    guard case let .object(fields) = node else {
      return nil
    }
    // An attribute the read did not carry stays `nil` (omitted); one it carried resolves to
    // `.some(value-or-nil)`, so a requested-but-empty attribute survives as an explicit null.
    func attribute<T>(_ key: FBAXKeys, _ extract: (FBJSONValue) -> T?) -> T?? {
      guard let raw = fields[key.rawValue] else {
        return nil
      }
      return .some(extract(raw))
    }
    func asString(_ value: FBJSONValue) -> String? {
      guard case let .string(string) = value else { return nil }
      return string
    }
    func asBool(_ value: FBJSONValue) -> Bool? {
      guard case let .bool(bool) = value else { return nil }
      return bool
    }
    func asStrings(_ value: FBJSONValue) -> [String]? {
      guard case let .array(values) = value else { return nil }
      return values.compactMap(asString)
    }
    func number(_ value: FBJSONValue?) -> Double? {
      switch value {
      case let .double(number): return number
      case let .int(number): return Double(number)
      default: return nil
      }
    }

    var element = FBAccessibilityDocumentElement(
      children: completeElements(from: fields[childrenKey] ?? .array([]))
    )
    element.label = attribute(.label, asString)
    element.identifier = attribute(.uniqueID, asString)
    element.type = attribute(.type, asString)
    element.title = attribute(.title, asString)
    element.help = attribute(.help, asString)
    element.roleDescription = attribute(.roleDescription, asString)
    element.subrole = attribute(.subrole, asString)
    element.placeholder = attribute(.placeholder, asString)
    element.enabled = attribute(.enabled, asBool)
    element.contentRequired = attribute(.contentRequired, asBool)
    element.expanded = attribute(.expanded, asBool)
    element.hidden = attribute(.hidden, asBool)
    element.focused = attribute(.focused, asBool)
    element.isRemote = attribute(.isRemote, asBool)
    element.customActions = attribute(.customActions, asStrings)
    element.traits = attribute(.traits, asStrings)
    element.pid = attribute(.pid) { if case let .int(pid) = $0 { return pid } else { return nil } }
    element.frame = attribute(.frameDict) { value in
      guard case let .object(frame) = value else { return nil }
      return FBAccessibilityFrame(
        x: number(frame["x"]), y: number(frame["y"]),
        width: number(frame["width"]), height: number(frame["height"])
      )
    }
    element.value = attribute(.value) { value in
      switch value {
      case let .string(string): return .string(string)
      case let .bool(bool): return .bool(bool)
      case let .int(int): return .int(int)
      case let .double(double): return .double(double)
      case .array, .object, .null: return nil
      }
    }
    return element
  }

  /// The serializer's own key for a node's children — not an `FBAXKeys` attribute, since it is a
  /// product of the traversal rather than something read off an element.
  private static let childrenKey = "children"

}

extension FBAccessibilityElementsResponse: CustomStringConvertible {
  public var description: String {
    "<FBAccessibilityElementsResponse: elements=\(Swift.type(of: elements)), profiling=\(String(describing: profilingData)), frameCoverage=\(String(describing: frameCoverage)), additionalFrameCoverage=\(String(describing: additionalFrameCoverage)), modal=\(String(describing: modal))>"
  }
}

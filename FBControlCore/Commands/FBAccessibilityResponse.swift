/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Profiling data collected during an accessibility operation. Provides
/// visibility into the performance characteristics of the AX subsystem.
public struct FBAccessibilityProfilingData: Sendable {

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

  /// The profiling data as a JSON-serializable dictionary. Times are in milliseconds.
  public func asDictionary() -> [String: NSNumber] {
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
/// **Not part of the serialized (CLI / gRPC) output** — see `FBAccessibilityElementsResponse.modal`. It
/// lets a host detect and classify a modal semantically (not by geometry) without changing the emitted
/// accessibility JSON.
public struct FBAccessibilityModalInfo: Sendable, Equatable {

  /// Who owns the modal: the system shell (SpringBoard — a system/permission alert) or the app itself
  /// (an in-app `UIAlertController`).
  public enum Kind: String, Sendable {
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

  /// A fullscreen modal / alert present over the read target, when one was detected. **Deliberately
  /// excluded from `asDictionary()`** so the serialized CLI / gRPC output is byte-stable — this is
  /// host-facing enrichment only, not part of the emitted accessibility payload.
  public let modal: FBAccessibilityModalInfo?

  public init(
    elements: FBJSONValue,
    profilingData: FBAccessibilityProfilingData? = nil,
    frameCoverage: Double? = nil,
    additionalFrameCoverage: Double? = nil,
    modal: FBAccessibilityModalInfo? = nil
  ) {
    self.elements = elements
    self.profilingData = profilingData
    self.frameCoverage = frameCoverage
    self.additionalFrameCoverage = additionalFrameCoverage
    self.modal = modal
  }

  /// A JSON-serializable dictionary with elements always embedded.
  /// Format: `{"elements": <elements>, "profile": <profile>, "coverage": <coverage>}`.
  /// `profile` and `coverage` are included only when the corresponding data is present.
  ///
  /// `modal` is intentionally **not** serialized here: it is host-facing enrichment, and emitting it
  /// would change the CLI / gRPC accessibility output. Keep it out of this method.
  public func asDictionary() -> [String: Any] {
    var dict: [String: Any] = ["elements": elements.toFoundationObject()]
    if let profilingData {
      dict["profile"] = profilingData.asDictionary()
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
}

extension FBAccessibilityElementsResponse: CustomStringConvertible {
  public var description: String {
    "<FBAccessibilityElementsResponse: elements=\(Swift.type(of: elements)), profiling=\(String(describing: profilingData)), frameCoverage=\(String(describing: frameCoverage)), additionalFrameCoverage=\(String(describing: additionalFrameCoverage)), modal=\(String(describing: modal))>"
  }
}

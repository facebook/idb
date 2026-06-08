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

/// Response object containing accessibility elements and optional profiling data.
///
/// `elements` is an `NSArray` (flat/nested) or `NSDictionary` (single element) —
/// the heterogeneous JSON payload produced by the serializer.
public struct FBAccessibilityElementsResponse {

  /// The accessibility elements. An NSArray (flat/nested) or NSDictionary (single element).
  public let elements: Any

  /// Profiling data collected during the operation, if profiling was enabled.
  public let profilingData: FBAccessibilityProfilingData?

  /// The proportion of the screen covered by accessibility element frames (0.0 - 1.0).
  /// Nil if coverage calculation was not requested. Low values suggest remote content.
  public let frameCoverage: Double?

  /// Additional coverage discovered via grid-based hit-testing for remote content.
  /// Nil if remote content discovery was not performed or found nothing.
  public let additionalFrameCoverage: Double?

  public init(
    elements: Any,
    profilingData: FBAccessibilityProfilingData?,
    frameCoverage: Double?,
    additionalFrameCoverage: Double?
  ) {
    self.elements = elements
    self.profilingData = profilingData
    self.frameCoverage = frameCoverage
    self.additionalFrameCoverage = additionalFrameCoverage
  }

  /// A JSON-serializable dictionary with elements always embedded.
  /// Format: `{"elements": <elements>, "profile": <profile>, "coverage": <coverage>}`.
  /// `profile` and `coverage` are included only when the corresponding data is present.
  public func asDictionary() -> [String: Any] {
    var dict: [String: Any] = ["elements": elements]
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
    "<FBAccessibilityElementsResponse: elements=\(Swift.type(of: elements)), profiling=\(String(describing: profilingData)), frameCoverage=\(String(describing: frameCoverage)), additionalFrameCoverage=\(String(describing: additionalFrameCoverage))>"
  }
}

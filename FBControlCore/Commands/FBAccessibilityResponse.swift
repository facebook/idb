/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Profiling data collected during an accessibility operation. Provides
/// visibility into the performance characteristics of the AX subsystem.
///
/// Still constructed from Objective-C (the `FBAccessibilityProfilingCollector`
/// in `FBSimulatorControl`), so this keeps an `@objc` designated initializer
/// and ObjC class name.
@objc(FBAccessibilityProfilingData)
public final class FBAccessibilityProfilingData: NSObject {

  /// The number of accessibility elements that were serialized.
  @objc public let elementCount: Int64

  /// The number of attribute fetches made on accessibility elements. Each
  /// property access (accessibilityLabel, accessibilityFrame, etc.) counts as one.
  @objc public let attributeFetchCount: Int64

  /// The number of XPC calls made to the simulator's accessibility service.
  @objc public let xpcCallCount: Int64

  /// The time spent in performWithTranslator (getting the translation object).
  @objc public let translationDuration: CFAbsoluteTime

  /// The time spent converting the translation object to a platform element.
  @objc public let elementConversionDuration: CFAbsoluteTime

  /// The time spent serializing the accessibility tree.
  @objc public let serializationDuration: CFAbsoluteTime

  /// The total time spent in XPC calls.
  @objc public let totalXPCDuration: CFAbsoluteTime

  /// The set of keys that were fetched during serialization. Useful for tests
  /// to verify which attributes were actually accessed.
  @objc public let fetchedKeys: NSSet

  @objc
  public init(
    elementCount: Int64,
    attributeFetchCount: Int64,
    xpcCallCount: Int64,
    translationDuration: CFAbsoluteTime,
    elementConversionDuration: CFAbsoluteTime,
    serializationDuration: CFAbsoluteTime,
    totalXPCDuration: CFAbsoluteTime,
    fetchedKeys: NSSet
  ) {
    self.elementCount = elementCount
    self.attributeFetchCount = attributeFetchCount
    self.xpcCallCount = xpcCallCount
    self.translationDuration = translationDuration
    self.elementConversionDuration = elementConversionDuration
    self.serializationDuration = serializationDuration
    self.totalXPCDuration = totalXPCDuration
    self.fetchedKeys = (fetchedKeys.copy() as? NSSet) ?? fetchedKeys
    super.init()
  }

  /// The profiling data as a JSON-serializable dictionary. Times are in milliseconds.
  @objc public func asDictionary() -> [String: NSNumber] {
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

  public override var description: String {
    String(
      format: "<%@: elements=%lld, xpc_calls=%lld, translation=%.2fms, serialization=%.2fms>",
      NSStringFromClass(type(of: self)),
      elementCount,
      xpcCallCount,
      translationDuration * 1000,
      serializationDuration * 1000
    )
  }
}

/// Response object containing accessibility elements and optional profiling data.
///
/// Still constructed from Objective-C (the `ResponseBuilder` category in
/// `FBSimulatorControl`), so this keeps an `@objc` designated initializer and
/// ObjC class name. `elements` is an `NSArray` (flat/nested) or `NSDictionary`
/// (single element).
@objc(FBAccessibilityElementsResponse)
public final class FBAccessibilityElementsResponse: NSObject {

  /// The accessibility elements. An NSArray (flat/nested) or NSDictionary (single element).
  @objc public let elements: Any

  /// Profiling data collected during the operation, if profiling was enabled.
  @objc public let profilingData: FBAccessibilityProfilingData?

  /// The proportion of the screen covered by accessibility element frames (0.0 - 1.0).
  /// Nil if coverage calculation was not requested. Low values suggest remote content.
  @objc public let frameCoverage: NSNumber?

  /// Additional coverage discovered via grid-based hit-testing for remote content.
  /// Nil if remote content discovery was not performed or found nothing.
  @objc public let additionalFrameCoverage: NSNumber?

  @objc
  public init(
    elements: Any,
    profilingData: FBAccessibilityProfilingData?,
    frameCoverage: NSNumber?,
    additionalFrameCoverage: NSNumber?
  ) {
    self.elements = elements
    self.profilingData = profilingData
    self.frameCoverage = frameCoverage
    self.additionalFrameCoverage = additionalFrameCoverage
    super.init()
  }

  /// A JSON-serializable dictionary with elements always embedded.
  /// Format: `{"elements": <elements>, "profile": <profile>, "coverage": <coverage>}`.
  /// `profile` and `coverage` are included only when the corresponding data is present.
  @objc public func asDictionary() -> [String: Any] {
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

  public override var description: String {
    "<\(NSStringFromClass(type(of: self))): elements=\(Swift.type(of: elements)), profiling=\(String(describing: profilingData)), frameCoverage=\(String(describing: frameCoverage)), additionalFrameCoverage=\(String(describing: additionalFrameCoverage))>"
  }
}

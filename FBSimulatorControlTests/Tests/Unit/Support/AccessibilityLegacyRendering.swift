/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// Untyped views of the legacy JSON output. They go through the real encoder, so an assertion
/// cannot pass on a value the encoder would never emit.
extension FBAccessibilityElementsResponse {

  func legacyJSONData() throws -> Data {
    try formattedOutputJSON(format: .default)
  }

  /// The legacy envelope as Foundation: `{"elements": ...}`.
  func legacyEnvelopeObject() throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: try legacyJSONData()) as? [String: Any])
  }

  /// Just the elements, legacy-spelled — an array for a tree, an object for a single element.
  func legacyElementsObject() -> Any {
    elements.legacyFoundationObject
  }
}

extension FBAccessibilityDocumentElement {

  /// This element alone, legacy-spelled, as Foundation.
  func legacyObject() -> [String: Any] {
    legacyFoundationObject
  }
}

extension FBAccessibilityDocumentElement {

  /// An element with just the attributes a marker match reads. All three are set to `.some(...)`, so an
  /// omitted one reads as "requested, and empty" rather than "not requested"; matching and geometry
  /// flatten the pair with `?? nil` and cannot tell the two apart. A test that needs the distinction
  /// should build its own element.
  static func testElement(
    label: String? = nil,
    identifier: String? = nil,
    frame: FBAccessibilityFrame? = nil
  ) -> FBAccessibilityDocumentElement {
    var element = FBAccessibilityDocumentElement()
    element.label = .some(label)
    element.identifier = .some(identifier)
    element.frame = .some(frame)
    return element
  }
}

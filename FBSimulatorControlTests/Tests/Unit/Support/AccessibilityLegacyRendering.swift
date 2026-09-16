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
extension AccessibilityElementsResponse {

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

extension AccessibilityDocumentElement {

  /// This element alone, legacy-spelled, as Foundation.
  func legacyObject() -> [String: Any] {
    legacyFoundationObject
  }
}

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

/// Untyped views of the legacy output, for assertions written against dictionaries.
///
/// The production path is typed end to end; these exist so a test can inspect what a consumer parsing
/// the emitted JSON actually receives. They deliberately go through the real encoder rather than
/// reaching into the model, so an assertion cannot pass on a value the encoder would never emit.
extension FBAccessibilityElementsResponse {

  /// The legacy envelope exactly as a caller receives it — through the production renderer, so a test
  /// cannot pass against bytes the renderer would never emit.
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

  /// An element carrying just the attributes a marker match reads, for tests that exercise matching and
  /// frame geometry without going through a serializer.
  ///
  /// All three attributes are always marked as read, so omitting one yields "requested, and empty"
  /// rather than "not requested" — the two states the doubly-optional model distinguishes. Matching and
  /// geometry flatten the pair with `?? nil` and cannot tell them apart, so this is unambiguous here; a
  /// test that turns on the distinction wants its own element rather than this helper.
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

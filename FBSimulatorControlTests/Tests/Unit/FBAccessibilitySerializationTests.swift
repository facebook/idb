/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// Golden characterization of the accessibility serializer's JSON output. These pin the exact
/// serialized bytes — in particular that a nil field is emitted as an explicit `null` and its key is
/// NOT dropped (a deserializing consumer distinguishes JSON `null` from a missing key, e.g. JS
/// `null` vs `undefined`). The serializer's internal value representation may change, but this output
/// must not: the same assertions guard the switch to a Sendable typed-JSON payload.
final class FBAccessibilitySerializationTests: XCTestCase {

  // A focused key set that keeps the golden small while covering present and absent (null) fields:
  // `.label` is present on every node, `.value`/`.uniqueID` are present on the root but absent on the
  // child, and `.title` is never produced by the remote element — so every node has a `null` field.
  private static let characterizationKeys: Set<FBAXKeys> = [.label, .value, .uniqueID, .title]

  // A two-node tree whose child omits `value`/`identifier`, so the child serializes those as `null`.
  private static func sampleTree() -> [String: Any] {
    [
      FBRemoteAutomationAXAttribute.label: "root",
      FBRemoteAutomationAXAttribute.value: "on",
      FBRemoteAutomationAXAttribute.identifier: "com.example.root",
      FBRemoteAutomationAXAttribute.children: [
        [FBRemoteAutomationAXAttribute.label: "child"] as [String: Any]
      ],
    ]
  }

  private func serializedJSON(nestedFormat: Bool) throws -> String {
    let elements = FBSimulatorRemoteAutomation.describeAllElements(
      fromTree: Self.sampleTree(), keys: Self.characterizationKeys, nestedFormat: nestedFormat, pid: 7
    )
    let response = FBAccessibilityElementsResponse(
      elements: .array(elements), profilingData: nil, frameCoverage: nil, additionalFrameCoverage: nil
    )
    let data = try JSONSerialization.data(withJSONObject: response.asDictionary(), options: .sortedKeys)
    return String(decoding: data, as: UTF8.self)
  }

  func testSerializedFlatJSONPreservesNullFields() throws {
    let json = try serializedJSON(nestedFormat: false)
    XCTAssertEqual(json, Self.expectedFlatJSON)
    // The nil field is an explicit `null`, key present — not dropped.
    XCTAssertTrue(json.contains("\"\(FBAXKeys.title.rawValue)\":null"), "nil title must serialize as null, got: \(json)")
  }

  func testSerializedNestedJSONPreservesNullFields() throws {
    let json = try serializedJSON(nestedFormat: true)
    XCTAssertEqual(json, Self.expectedNestedJSON)
    XCTAssertTrue(json.contains("\"\(FBAXKeys.title.rawValue)\":null"), "nil title must serialize as null, got: \(json)")
  }

  // An off-screen element (e.g. a SpringBoard icon) can report a non-finite frame coordinate. JSON
  // has no representation for infinity/NaN, so a non-finite value must serialize as null rather than
  // let JSONSerialization throw an uncaught NSException ("Invalid number value (infinite) in JSON
  // write") that terminates the process.
  func testSerializedJSONSanitizesNonFiniteFrame() throws {
    let frameDict = CGRectCreateDictionaryRepresentation(CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 20)) as NSDictionary
    let tree: [String: Any] = [
      FBRemoteAutomationAXAttribute.label: "icon",
      FBRemoteAutomationAXAttribute.frame: frameDict,
    ]
    let elements = FBSimulatorRemoteAutomation.describeAllElements(
      fromTree: tree, keys: [.label, .frameDict], nestedFormat: false, pid: 7
    )
    let response = FBAccessibilityElementsResponse(
      elements: .array(elements), profilingData: nil, frameCoverage: nil, additionalFrameCoverage: nil
    )
    let data = try JSONSerialization.data(withJSONObject: response.asDictionary(), options: .sortedKeys)
    let json = String(decoding: data, as: UTF8.self)
    XCTAssertTrue(json.contains("\"x\":null"), "non-finite frame x must serialize as null, got: \(json)")
    XCTAssertTrue(json.contains("\"height\":20"), "finite frame values must be preserved, got: \(json)")
  }

  private static let expectedFlatJSON =
    #"{"elements":[{"AXLabel":"root","AXUniqueId":"com.example.root","AXValue":"on","title":null},{"AXLabel":"child","AXUniqueId":null,"AXValue":null,"title":null}]}"#

  private static let expectedNestedJSON =
    #"{"elements":[{"AXLabel":"root","AXUniqueId":"com.example.root","AXValue":"on","children":[{"AXLabel":"child","AXUniqueId":null,"AXValue":null,"children":[],"title":null}],"title":null}]}"#
}

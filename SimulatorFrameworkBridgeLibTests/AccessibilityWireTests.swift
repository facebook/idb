/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeSupport
import XCTest

final class AccessibilityWireTests: XCTestCase {
  func testNestedNonFiniteNumbersBecomeNullWithoutChangingOtherScalars() throws {
    let response: [String: Any] = [
      "ok": true,
      "values": [Double.nan, Double.infinity, -Double.infinity, ["nested": Double.nan]],
      "integer": NSNumber(value: Int64.max),
      "fraction": 1.25,
      "false": false,
      "string": "infinity",
      "null": NSNull(),
    ]
    let encoded = FBAccessibilityService.serializeResponse(response)
    let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    XCTAssertEqual(
      decoded as NSDictionary,
      [
        "ok": true,
        "values": [NSNull(), NSNull(), NSNull(), ["nested": NSNull()]],
        "integer": NSNumber(value: Int64.max),
        "fraction": 1.25,
        "false": false,
        "string": "infinity",
        "null": NSNull(),
      ] as NSDictionary)
    let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
    XCTAssertTrue(json.contains(#""ok":true"#))
    XCTAssertTrue(json.contains(#""false":false"#))
  }

  func testUnsupportedNestedValuesKeepTheSerializationFallback() {
    let response: [String: Any] = ["ok": true, "values": [["date": Date()]]]
    XCTAssertEqual(FBAccessibilityService.serializeResponse(response), Data(#"{"ok":false,"error":"response serialization failed"}"#.utf8))
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

final class AccessibilityWireTests: XCTestCase {
  func testNonObjectFramesAreRejectedAndClearShutdown() {
    for input in ["", "not json", "[]", "[{}]", "null", "true", "42", "\"shutdown\""] {
      var shutdown = ObjCBool(true)
      let response = FBAXBridgeHandleRequestData(Data(input.utf8), &shutdown)
      XCTAssertEqual(
        response as NSDictionary,
        [
          "ok": false, "error": "malformed request frame", "error_kind": "bad_request",
        ] as NSDictionary, input)
      XCTAssertFalse(shutdown.boolValue, input)
    }
  }

  func testShutdownObjectSurvivesDecoding() {
    var shutdown = ObjCBool(false)
    let response = FBAXBridgeHandleRequestData(Data(#"{"verb":"shutdown","pid":0}"#.utf8), &shutdown)
    XCTAssertEqual(response as NSDictionary, ["ok": true, "shutdown": true] as NSDictionary)
    XCTAssertTrue(shutdown.boolValue)
  }

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
    let encoded = FBAXBridgeSerializeResponse(response)
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
    XCTAssertEqual(FBAXBridgeSerializeResponse(response), Data(#"{"ok":false,"error":"response serialization failed"}"#.utf8))
  }
}

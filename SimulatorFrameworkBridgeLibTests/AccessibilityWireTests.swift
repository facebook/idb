/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeSupport
import Testing

@Suite
struct AccessibilityWireTests {
  @Test
  func nestedNonFiniteNumbersBecomeNullWithoutChangingOtherScalars() throws {
    let response: [String: Any] = [
      "ok": true,
      "values": [Double.nan, Double.infinity, -Double.infinity, ["nested": Double.nan]],
      "integer": NSNumber(value: Int64.max),
      "fraction": 1.25,
      "false": false,
      "string": "infinity",
      "null": NSNull(),
    ]
    let encoded = AccessibilityService.serializeResponse(response)
    let object = try JSONSerialization.jsonObject(with: encoded)
    let decoded = try #require(object as? [String: Any])
    #expect(
      decoded as NSDictionary == [
        "ok": true,
        "values": [NSNull(), NSNull(), NSNull(), ["nested": NSNull()]],
        "integer": NSNumber(value: Int64.max),
        "fraction": 1.25,
        "false": false,
        "string": "infinity",
        "null": NSNull(),
      ] as NSDictionary)
    let json = try #require(String(data: encoded, encoding: .utf8))
    #expect(json.contains(#""ok":true"#))
    #expect(json.contains(#""false":false"#))
  }

  @Test
  func unsupportedNestedValuesKeepTheSerializationFallback() {
    let response: [String: Any] = ["ok": true, "values": [["date": Date()]]]
    #expect(AccessibilityService.serializeResponse(response) == Data(#"{"ok":false,"error":"response serialization failed"}"#.utf8))
  }
}

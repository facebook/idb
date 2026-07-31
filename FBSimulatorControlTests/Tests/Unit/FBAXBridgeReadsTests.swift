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

/// Coverage for the axbridge read path that does not require a live simulator: the guest response
/// envelope parsing (`FBAXBridgeResponse`) and the tree -> shared-serializer integration that makes
/// the axbridge output identical to the testmanagerd backend (both feed `describeAllElements`).
final class FBAXBridgeReadsTests: XCTestCase {

  private func envelope(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
  }

  // MARK: - FBAXBridgeResponse envelope parsing

  func testParsesTreeFromOkEnvelope() throws {
    let tree: [String: Any] = [
      FBRemoteAutomationAXAttribute.label: "General",
      FBRemoteAutomationAXAttribute.identifier: "com.apple.settings.general",
    ]
    let data = try envelope(["ok": true, "tree": tree])
    let parsed = try FBAXBridgeResponse.tree(fromResponse: data, pid: 42)
    XCTAssertEqual(parsed[FBRemoteAutomationAXAttribute.label] as? String, "General")
    XCTAssertEqual(parsed[FBRemoteAutomationAXAttribute.identifier] as? String, "com.apple.settings.general")
  }

  func testSurfacesGuestErrorMessage() throws {
    let data = try envelope(["ok": false, "error": "no application element for pid 7"])
    XCTAssertThrowsError(try FBAXBridgeResponse.tree(fromResponse: data, pid: 7)) { error in
      // The guest's own error message is carried through so callers see the real cause.
      XCTAssertTrue("\(error)".contains("no application element for pid 7"), "unexpected error: \(error)")
    }
  }

  func testThrowsOnMalformedResponse() {
    let data = Data("this is not json".utf8)
    XCTAssertThrowsError(try FBAXBridgeResponse.tree(fromResponse: data, pid: 1))
  }

  func testThrowsWhenOkButNoTree() throws {
    let data = try envelope(["ok": true])
    XCTAssertThrowsError(try FBAXBridgeResponse.tree(fromResponse: data, pid: 1))
  }

  func testThrowsWhenNotOk() throws {
    // `ok` missing/false with no `error` still fails rather than yielding an empty tree.
    let data = try envelope(["tree": [FBRemoteAutomationAXAttribute.label: "x"]])
    XCTAssertThrowsError(try FBAXBridgeResponse.tree(fromResponse: data, pid: 1))
  }

  // MARK: - FBAXBridgeResponse hit-test parsing

  func testHitTestParsesHitNode() throws {
    let node: [String: Any] = [FBRemoteAutomationAXAttribute.identifier: "com.apple.settings.general"]
    let data = try envelope(["ok": true, "tree": node])
    let parsed = try FBAXBridgeResponse.hitTest(fromResponse: data, pid: 42)
    XCTAssertEqual(parsed?[FBRemoteAutomationAXAttribute.identifier] as? String, "com.apple.settings.general")
  }

  func testHitTestReturnsNilForEmptyResult() throws {
    // `{ok:true, empty:true}` is "no element at the point" — a valid empty result, returned as nil,
    // not conflated with a reader failure.
    let data = try envelope(["ok": true, "empty": true])
    XCTAssertNil(try FBAXBridgeResponse.hitTest(fromResponse: data, pid: 42))
  }

  func testHitTestThrowsOnFailure() throws {
    // A failure (`ok:false`) is distinct from an empty result and is surfaced with the guest message.
    let data = try envelope(["ok": false, "error": "AXUIElementCopyElementAtPosition unavailable"])
    XCTAssertThrowsError(try FBAXBridgeResponse.hitTest(fromResponse: data, pid: 42)) { error in
      XCTAssertTrue("\(error)".contains("AXUIElementCopyElementAtPosition unavailable"), "unexpected error: \(error)")
    }
  }

  func testHitTestThrowsWhenOkButNoTreeOrEmpty() throws {
    let data = try envelope(["ok": true])
    XCTAssertThrowsError(try FBAXBridgeResponse.hitTest(fromResponse: data, pid: 1))
  }

  // MARK: - Tree -> shared serializer integration

  func testGuestTreeFeedsSharedSerializerSchema() throws {
    // A guest envelope carrying a small XC_kAXXC* tree round-trips through the same path the
    // testmanagerd backend uses (`FBAXBridgeResponse.tree` -> `describeAllElements`), producing the
    // shared schema: the child is a Button (automationType 9) with its identifier, proving the
    // axbridge output is byte-compatible with the shared serializer rather than a bespoke shape.
    let tree: [String: Any] = [
      FBRemoteAutomationAXAttribute.label: "root",
      FBRemoteAutomationAXAttribute.children: [
        [
          FBRemoteAutomationAXAttribute.label: "General",
          FBRemoteAutomationAXAttribute.identifier: "com.apple.settings.general",
          FBRemoteAutomationAXAttribute.automationType: 9,
          FBRemoteAutomationAXAttribute.children: [[String: Any]](),
        ] as [String: Any]
      ],
    ]
    let data = try envelope(["ok": true, "tree": tree])
    let parsed = try FBAXBridgeResponse.tree(fromResponse: data, pid: 99)

    let elements = FBAXTreeSerialization.describeAllElements(
      fromTree: parsed, keys: FBAXKeys.defaultSet, nestedFormat: false, pid: 99
    )
    XCTAssertEqual(elements.count, 2, "expected the root plus its one child, flattened")

    let response = FBAccessibilityElementsResponse(
      elements: .array(elements), profilingData: nil, frameCoverage: nil, additionalFrameCoverage: nil
    )
    let json = try JSONSerialization.data(withJSONObject: response.asDictionary(), options: .sortedKeys)
    let serialized = String(data: json, encoding: .utf8) ?? ""
    XCTAssertTrue(serialized.contains("com.apple.settings.general"), "missing identifier in \(serialized)")
    // automationType 9 maps to the readable XCUIElementType name via the shared serializer.
    XCTAssertTrue(serialized.contains("\"role\":\"Button\""), "role not mapped in \(serialized)")
  }
}

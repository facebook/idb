/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

final class AccessibilityArgumentsTests: XCTestCase {
  func testRequestPreservesFlagValuesAndFoundationCoercion() {
    let request = FBAXBridgeRequestFromArguments(
      "perform",
      [
        "--pid", "12suffix", "--max-depth", "nonsense", "--max-nodes", "-3",
        "--translator-vocabulary", "YES", "--snapshot-tree", "0", "--explain-unreachable", "true",
        "--attributes", "label,,value,", "--x", "1.5tail", "--y", "bad",
        "--method", "window-server", "--action", "press", "--value", "",
        "--setting", "voiceover", "--enabled", "false", "--assert-key", "label", "--assert-value", "Hello",
      ])
    let expected: [String: Any] = [
      "verb": "perform", "pid": 12, "maxDepth": 0, "maxNodes": -3,
      "translatorVocabulary": true, "snapshotTree": false, "explainUnreachable": true,
      "attributes": ["label", "", "value", ""], "x": 1.5, "y": 0,
      "method": "window-server", "action": "press", "value": "", "setting": "voiceover",
      "enabled": false, "assertKey": "label", "assertValue": "Hello",
    ]
    XCTAssertEqual(request as NSDictionary, expected as NSDictionary)
  }

  func testRequestUsesLastDuplicateAndIgnoresUnknownAndDanglingFlags() {
    let request = FBAXBridgeRequestFromArguments(
      "describe",
      [
        "--pid", "10", "--unknown", "ignored", "--pid", "20", "--max-depth",
      ])
    XCTAssertEqual(request as NSDictionary, ["verb": "describe", "pid": 20] as NSDictionary)
    XCTAssertEqual(
      FBAXBridgeRequestFromArguments("shutdown", []) as NSDictionary,
      ["verb": "shutdown"] as NSDictionary)
  }

  func testEnabledOnlyCoercesExactBooleanSpellings() {
    for (input, expected): (String, Any) in [("true", true), ("false", false), ("YES", "YES"), ("1", "1"), ("", "")] {
      let request = FBAXBridgeRequestFromArguments("settings-set", ["--enabled", input])
      XCTAssertEqual(request as NSDictionary, ["verb": "settings-set", "enabled": expected] as NSDictionary)
    }
  }

  func testServeOptionsUseFirstDuplicateEvenWhenInvalid() {
    XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(["--idle-timeout", "bad", "--idle-timeout", "45"], 300), 300)
    XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(["--idle-timeout", "45", "--idle-timeout", "90"], 300), 45)
    XCTAssertFalse(FBAXBridgeExitOnDisconnectForTesting(["--exit-on-disconnect", "0", "--exit-on-disconnect", "1"]))
    XCTAssertTrue(FBAXBridgeExitOnDisconnectForTesting(["--exit-on-disconnect", "YES"]))
    XCTAssertFalse(FBAXBridgeExitOnDisconnectForTesting(["--exit-on-disconnect"]))
  }

  func testServeTimeoutKeepsScannerWhitespaceAndSignHandling() {
    XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(["--idle-timeout", "  +45"], 300), 45)
    XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(["--idle-timeout", "45tail"], 300), 300)
  }
}

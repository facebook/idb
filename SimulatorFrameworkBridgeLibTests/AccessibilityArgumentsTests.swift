/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
@_implementationOnly import SimulatorFrameworkBridgeSupport
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

  func testAutomationModeHonorsBothValuesAndPreservesOmission() {
    for (input, expected) in [("1", true), ("0", false)] {
      let request = FBAXBridgeRequestFromArguments("describe", ["--automation-mode", input])
      XCTAssertEqual(request["automationMode"] as? Bool, expected)
    }
    XCTAssertNil(FBAXBridgeRequestFromArguments("describe", ["--pid", "42"])["automationMode"])
  }

  func testServeOptionsUseFirstDuplicateEvenWhenInvalid() {
    XCTAssertEqual(FBAXBridgeArguments.idleTimeout(arguments: ["--idle-timeout", "bad", "--idle-timeout", "45"], fallback: 300), 300)
    XCTAssertEqual(FBAXBridgeArguments.idleTimeout(arguments: ["--idle-timeout", "45", "--idle-timeout", "90"], fallback: 300), 45)
    XCTAssertFalse(FBAXBridgeArguments.exitOnDisconnect(arguments: ["--exit-on-disconnect", "0", "--exit-on-disconnect", "1"]))
    XCTAssertTrue(FBAXBridgeArguments.exitOnDisconnect(arguments: ["--exit-on-disconnect", "YES"]))
    XCTAssertFalse(FBAXBridgeArguments.exitOnDisconnect(arguments: ["--exit-on-disconnect"]))
  }

  func testServeTimeoutKeepsScannerWhitespaceAndSignHandling() {
    XCTAssertEqual(FBAXBridgeArguments.idleTimeout(arguments: ["--idle-timeout", "  +45"], fallback: 300), 45)
    XCTAssertEqual(FBAXBridgeArguments.idleTimeout(arguments: ["--idle-timeout", "45tail"], fallback: 300), 300)
  }

  func testStartupTimeoutIsOptionalAndUsesServeOptionParsing() {
    XCTAssertNil(FBAXBridgeArguments.startupTimeout(arguments: []))
    for value in ["0", "-1", "bad", "12tail"] {
      XCTAssertNil(FBAXBridgeArguments.startupTimeout(arguments: ["--startup-timeout", value]))
    }
    XCTAssertNil(FBAXBridgeArguments.startupTimeout(arguments: ["--startup-timeout"]))
    XCTAssertNil(FBAXBridgeArguments.startupTimeout(arguments: ["--startup-timeout", "bad", "--startup-timeout", "10"]))
    XCTAssertEqual(FBAXBridgeArguments.startupTimeout(arguments: ["--startup-timeout", "  +10", "--startup-timeout", "20"]), 10)
    XCTAssertEqual(FBAXBridgeArguments.startupTimeout(arguments: ["--startup-timeout", String(Int32.max)]), Int32.max)
  }

}

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

final class BridgeServeOptionsTests: XCTestCase {

  func testServeBacklogAccommodatesConcurrentProbes() {
    // A full backlog can reject a probe with ECONNREFUSED, which is indistinguishable from no listener.
    // Leave room for competing hosts to connect and learn that the single-threaded guest is busy.
    XCTAssertEqual(BridgeServer.serveBacklog, 16)
  }

  func testExitOnDisconnectIsOffUnlessAsked() {
    XCTAssertFalse(BridgeServeOptions.exitOnDisconnect(arguments: []))
    XCTAssertFalse(BridgeServeOptions.exitOnDisconnect(arguments: ["--idle-timeout", "30"]))
  }

  func testExitOnDisconnectIsHonouredWhenAsked() {
    XCTAssertTrue(BridgeServeOptions.exitOnDisconnect(arguments: ["--exit-on-disconnect", "1"]))
    XCTAssertTrue(BridgeServeOptions.exitOnDisconnect(arguments: ["--idle-timeout", "30", "--exit-on-disconnect", "1"]))
  }

  func testExitOnDisconnectCanBeTurnedOffExplicitly() {
    XCTAssertFalse(BridgeServeOptions.exitOnDisconnect(arguments: ["--exit-on-disconnect", "0"]))
  }

  func testAnIdleTimeoutOnTheCommandLineIsHonoured() {
    XCTAssertEqual(BridgeServeOptions.idleTimeout(arguments: ["--idle-timeout", "45"], fallback: 300), 45)
  }

  func testAServeWithNoIdleTimeoutUsesTheDefault() {
    XCTAssertEqual(BridgeServeOptions.idleTimeout(arguments: [], fallback: 300), 300)
    XCTAssertEqual(BridgeServeOptions.idleTimeout(arguments: ["--something-else", "1"], fallback: 300), 300)
    XCTAssertEqual(BridgeServer.defaultIdleTimeoutSeconds, 300)
  }

  func testAnUnusableIdleTimeoutFallsBackToTheDefault() {
    XCTAssertEqual(BridgeServeOptions.idleTimeout(arguments: ["--idle-timeout", "0"], fallback: 300), 300)
    XCTAssertEqual(BridgeServeOptions.idleTimeout(arguments: ["--idle-timeout", "-5"], fallback: 300), 300)
    XCTAssertEqual(BridgeServeOptions.idleTimeout(arguments: ["--idle-timeout", "soon"], fallback: 300), 300)
    XCTAssertEqual(BridgeServeOptions.idleTimeout(arguments: ["--idle-timeout", "12x"], fallback: 300), 300)
    XCTAssertEqual(BridgeServeOptions.idleTimeout(arguments: ["--idle-timeout"], fallback: 300), 300)
  }

  func testServeOptionsUseFirstDuplicateEvenWhenInvalid() {
    XCTAssertEqual(BridgeServeOptions.idleTimeout(arguments: ["--idle-timeout", "bad", "--idle-timeout", "45"], fallback: 300), 300)
    XCTAssertEqual(BridgeServeOptions.idleTimeout(arguments: ["--idle-timeout", "45", "--idle-timeout", "90"], fallback: 300), 45)
    XCTAssertFalse(BridgeServeOptions.exitOnDisconnect(arguments: ["--exit-on-disconnect", "0", "--exit-on-disconnect", "1"]))
    XCTAssertTrue(BridgeServeOptions.exitOnDisconnect(arguments: ["--exit-on-disconnect", "YES"]))
    XCTAssertFalse(BridgeServeOptions.exitOnDisconnect(arguments: ["--exit-on-disconnect"]))
  }

  func testServeTimeoutKeepsScannerWhitespaceAndSignHandling() {
    XCTAssertEqual(BridgeServeOptions.idleTimeout(arguments: ["--idle-timeout", "  +45"], fallback: 300), 45)
    XCTAssertEqual(BridgeServeOptions.idleTimeout(arguments: ["--idle-timeout", "45tail"], fallback: 300), 300)
  }

  func testStartupTimeoutIsOptionalAndUsesServeOptionParsing() {
    XCTAssertNil(BridgeServeOptions.startupTimeout(arguments: []))
    for value in ["0", "-1", "bad", "12tail"] {
      XCTAssertNil(BridgeServeOptions.startupTimeout(arguments: ["--startup-timeout", value]))
    }
    XCTAssertNil(BridgeServeOptions.startupTimeout(arguments: ["--startup-timeout"]))
    XCTAssertNil(BridgeServeOptions.startupTimeout(arguments: ["--startup-timeout", "bad", "--startup-timeout", "10"]))
    XCTAssertEqual(BridgeServeOptions.startupTimeout(arguments: ["--startup-timeout", "  +10", "--startup-timeout", "20"]), 10)
    XCTAssertEqual(BridgeServeOptions.startupTimeout(arguments: ["--startup-timeout", String(Int32.max)]), Int32.max)
  }
}

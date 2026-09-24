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

final class AccessibilityServiceServerTests: XCTestCase {

  func testServeBacklogAccommodatesConcurrentProbes() {
    // A full backlog can reject a probe with ECONNREFUSED, which is indistinguishable from no listener.
    // Leave room for competing hosts to connect and learn that the single-threaded guest is busy.
    XCTAssertEqual(FBAXBridgeServer.serveBacklog, 16)
  }

  func testExitOnDisconnectIsOffUnlessAsked() {
    XCTAssertFalse(FBAXBridgeArguments.exitOnDisconnect(arguments: []))
    XCTAssertFalse(FBAXBridgeArguments.exitOnDisconnect(arguments: ["--idle-timeout", "30"]))
  }

  func testExitOnDisconnectIsHonouredWhenAsked() {
    XCTAssertTrue(FBAXBridgeArguments.exitOnDisconnect(arguments: ["--exit-on-disconnect", "1"]))
    XCTAssertTrue(FBAXBridgeArguments.exitOnDisconnect(arguments: ["--idle-timeout", "30", "--exit-on-disconnect", "1"]))
  }

  func testExitOnDisconnectCanBeTurnedOffExplicitly() {
    XCTAssertFalse(FBAXBridgeArguments.exitOnDisconnect(arguments: ["--exit-on-disconnect", "0"]))
  }

  func testAnIdleTimeoutOnTheCommandLineIsHonoured() {
    XCTAssertEqual(FBAXBridgeArguments.idleTimeout(arguments: ["--idle-timeout", "45"], fallback: 300), 45)
  }

  func testAServeWithNoIdleTimeoutUsesTheDefault() {
    XCTAssertEqual(FBAXBridgeArguments.idleTimeout(arguments: [], fallback: 300), 300)
    XCTAssertEqual(FBAXBridgeArguments.idleTimeout(arguments: ["--something-else", "1"], fallback: 300), 300)
    XCTAssertEqual(FBAXBridgeServer.defaultIdleTimeoutSeconds, 300)
  }

  func testAnUnusableIdleTimeoutFallsBackToTheDefault() {
    XCTAssertEqual(FBAXBridgeArguments.idleTimeout(arguments: ["--idle-timeout", "0"], fallback: 300), 300)
    XCTAssertEqual(FBAXBridgeArguments.idleTimeout(arguments: ["--idle-timeout", "-5"], fallback: 300), 300)
    XCTAssertEqual(FBAXBridgeArguments.idleTimeout(arguments: ["--idle-timeout", "soon"], fallback: 300), 300)
    XCTAssertEqual(FBAXBridgeArguments.idleTimeout(arguments: ["--idle-timeout", "12x"], fallback: 300), 300)
    XCTAssertEqual(FBAXBridgeArguments.idleTimeout(arguments: ["--idle-timeout"], fallback: 300), 300)
  }
}

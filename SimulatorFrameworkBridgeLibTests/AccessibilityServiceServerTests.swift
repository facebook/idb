/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

final class AccessibilityServiceServerTests: XCTestCase {

  func testServeBacklogAccommodatesConcurrentProbes() {
    // A full backlog can reject a probe with ECONNREFUSED, which is indistinguishable from no listener.
    // Leave room for competing hosts to connect and learn that the single-threaded guest is busy.
    XCTAssertEqual(FBAXBridgeServeBacklogForTesting(), 16)
  }

  func testExitOnDisconnectIsOffUnlessAsked() {
    XCTAssertFalse(FBAXBridgeExitOnDisconnectForTesting([]))
    XCTAssertFalse(FBAXBridgeExitOnDisconnectForTesting(["--idle-timeout", "30"]))
  }

  func testExitOnDisconnectIsHonouredWhenAsked() {
    XCTAssertTrue(FBAXBridgeExitOnDisconnectForTesting(["--exit-on-disconnect", "1"]))
    XCTAssertTrue(FBAXBridgeExitOnDisconnectForTesting(["--idle-timeout", "30", "--exit-on-disconnect", "1"]))
  }

  func testExitOnDisconnectCanBeTurnedOffExplicitly() {
    XCTAssertFalse(FBAXBridgeExitOnDisconnectForTesting(["--exit-on-disconnect", "0"]))
  }

  func testAnIdleTimeoutOnTheCommandLineIsHonoured() {
    XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(["--idle-timeout", "45"], 300), 45)
  }

  func testAServeWithNoIdleTimeoutUsesTheDefault() {
    XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting([], 300), 300)
    XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(["--something-else", "1"], 300), 300)
    XCTAssertEqual(FBAXBridgeDefaultIdleTimeoutForTesting(), 300)
  }

  func testAnUnusableIdleTimeoutFallsBackToTheDefault() {
    XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(["--idle-timeout", "0"], 300), 300)
    XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(["--idle-timeout", "-5"], 300), 300)
    XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(["--idle-timeout", "soon"], 300), 300)
    XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(["--idle-timeout", "12x"], 300), 300)
    XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(["--idle-timeout"], 300), 300)
  }

  func testAMalformedFrameUsesTheServiceBadRequestEnvelope() {
    var shutdownRequested = ObjCBool(true)
    let response = FBAXBridgeHandleRequestData(Data("not json".utf8), &shutdownRequested)

    XCTAssertEqual(response["ok"] as? NSNumber, NSNumber(value: false))
    XCTAssertEqual(response["error"] as? String, "malformed request frame")
    XCTAssertEqual(response["error_kind"] as? String, "bad_request")
    XCTAssertFalse(shutdownRequested.boolValue)
  }

  func testAShutdownFrameReportsItsControlSignalBesideTheResponse() throws {
    let request = try JSONSerialization.data(withJSONObject: ["verb": "shutdown"])
    var shutdownRequested = ObjCBool(false)
    let response = FBAXBridgeHandleRequestData(request, &shutdownRequested)

    XCTAssertEqual(response["ok"] as? NSNumber, NSNumber(value: true))
    XCTAssertTrue(shutdownRequested.boolValue)
  }
}

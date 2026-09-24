/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

final class AccessibilityDisplayTests: XCTestCase {
  override func tearDown() {
    FBAXBridgeSetRuntimeForTesting(nil)
    super.tearDown()
  }

  func testDisplayInventoryPreservesRuntimeIdentitiesWithoutQueryingApplications() {
    let runtime = FBAXFakeRuntime()
    runtime.displayInventoryOutcome = .available([
      FBAXDisplayIdentity(uniqueID: "outer", displayID: 42),
      FBAXDisplayIdentity(uniqueID: "continuous-inner", displayID: 71),
    ])
    FBAXBridgeSetRuntimeForTesting(runtime)
    let request = FBAXBridgeRequestFromArguments("displays", [])
    XCTAssertEqual(request as NSDictionary, ["verb": "displays"])
    let response = FBAXBridgeHandleRequest(request)
    XCTAssertEqual(
      response as NSDictionary,
      [
        "ok": true,
        "displays": [["uniqueID": "outer", "displayID": 42], ["uniqueID": "continuous-inner", "displayID": 71]],
      ])
    XCTAssertEqual(runtime.operations as NSArray, ["displayInventory"])
    XCTAssertEqual(runtime.hitTestCount, 0)
    XCTAssertTrue(runtime.automationModeWrites.count == 0)
  }

  func testUnsupportedInventoryIsDistinctFromEmptyInventoryAndReaderFailure() {
    let runtime = FBAXFakeRuntime()
    FBAXBridgeSetRuntimeForTesting(runtime)
    runtime.displayInventoryOutcome = .unavailable("No display manager")
    XCTAssertEqual(
      FBAXBridgeHandleRequest(["verb": "displays"]) as NSDictionary,
      [
        "ok": false, "error": "No display manager", "error_kind": "capability_unavailable",
      ])
    runtime.displayInventoryOutcome = .failed("Duplicate identity")
    XCTAssertEqual(
      FBAXBridgeHandleRequest(["verb": "displays"]) as NSDictionary,
      [
        "ok": false, "error": "Duplicate identity", "error_kind": "reader_unavailable",
      ])
    runtime.displayInventoryOutcome = .available([])
    XCTAssertEqual(FBAXBridgeHandleRequest(["verb": "displays"]) as NSDictionary, ["ok": true, "displays": []])
  }

  func testDisplayInventoryExceptionIsContainedAndNextReadRecovers() {
    let runtime = FBAXFakeRuntime()
    FBAXBridgeSetRuntimeForTesting(runtime)
    runtime.raiseOnOperation = "displayInventory"
    XCTAssertEqual(
      FBAXBridgeHandleRequest(["verb": "displays"]) as NSDictionary,
      [
        "ok": false, "error": "the reader raised while answering: injected displayInventory", "error_kind": "reader_unavailable",
      ])
    runtime.raiseOnOperation = nil
    XCTAssertEqual(FBAXBridgeHandleRequest(["verb": "displays"])["ok"] as? Bool, true)
    XCTAssertEqual(runtime.operations as NSArray, ["displayInventory", "displayInventory"])
  }

}

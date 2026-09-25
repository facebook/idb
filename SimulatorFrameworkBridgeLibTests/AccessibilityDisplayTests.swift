/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeRuntime
@_implementationOnly import SimulatorFrameworkBridgeSupport
import XCTest

final class AccessibilityDisplayTests: XCTestCase {
  override func tearDown() {
    FBAXClientProvider.setRuntimeForTesting(nil)
    super.tearDown()
  }

  func testDisplayInventoryPreservesRuntimeIdentitiesWithoutQueryingApplications() {
    let runtime = FBAXFakeRuntime()
    runtime.displayInventoryOutcome = .available([
      FBAXDisplayIdentity(uniqueID: "outer", displayID: 42),
      FBAXDisplayIdentity(uniqueID: "continuous-inner", displayID: 71),
    ])
    FBAXClientProvider.setRuntimeForTesting(runtime)
    let request = FBAXBridgeArguments.request(action: "displays", arguments: [])
    XCTAssertEqual(request as NSDictionary, ["verb": "displays"])
    let response = FBAccessibilityService.handleRequest(request)
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
    FBAXClientProvider.setRuntimeForTesting(runtime)
    runtime.displayInventoryOutcome = .unavailable("No display manager")
    XCTAssertEqual(
      FBAccessibilityService.handleRequest(["verb": "displays"]) as NSDictionary,
      [
        "ok": false, "error": "No display manager", "error_kind": "capability_unavailable",
      ])
    runtime.displayInventoryOutcome = .failed("Duplicate identity")
    XCTAssertEqual(
      FBAccessibilityService.handleRequest(["verb": "displays"]) as NSDictionary,
      [
        "ok": false, "error": "Duplicate identity", "error_kind": "reader_unavailable",
      ])
    runtime.displayInventoryOutcome = .available([])
    XCTAssertEqual(FBAccessibilityService.handleRequest(["verb": "displays"]) as NSDictionary, ["ok": true, "displays": []])
  }

  func testDisplayInventoryExceptionIsContainedAndNextReadRecovers() {
    let runtime = FBAXFakeRuntime()
    FBAXClientProvider.setRuntimeForTesting(runtime)
    runtime.raiseOnOperation = "displayInventory"
    XCTAssertEqual(
      FBAccessibilityService.handleRequest(["verb": "displays"]) as NSDictionary,
      [
        "ok": false, "error": "the reader raised while answering: injected displayInventory", "error_kind": "reader_unavailable",
      ])
    runtime.raiseOnOperation = nil
    XCTAssertEqual(FBAccessibilityService.handleRequest(["verb": "displays"])["ok"] as? Bool, true)
    XCTAssertEqual(runtime.operations as NSArray, ["displayInventory", "displayInventory"])
  }

}

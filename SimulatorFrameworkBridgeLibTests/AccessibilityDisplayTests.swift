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
        "displayScopedInteractions": true, "displayScopedTrees": true, "displayScopedQuiescence": true,
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
    XCTAssertEqual(FBAccessibilityService.handleRequest(["verb": "displays"]) as NSDictionary, ["ok": true, "displayScopedInteractions": true, "displayScopedTrees": true, "displayScopedQuiescence": true, "displays": []])
  }

  private func window(_ label: String, displayID: Any?) -> FBAXFakeElement {
    let element = FBAXFakeElement.readable("UIWindow")
    var attributes: [String: Any] = [
      "XC_kAXXCAttributeElementType": "UIWindow",
      "XC_kAXXCAttributeLabel": label,
      "XC_kAXXCAttributeFrame": ["X": 0, "Y": 0, "Width": 400, "Height": 600],
    ]
    attributes["XC_kAXXCAttributeWindowDisplayId"] = displayID
    element.attributes = attributes
    return element
  }

  func testSameProcessWindowsAreFilteredByDisplayDespiteOverlappingFrames() throws {
    for snapshot in [false, true] {
      let runtime = FBAXFakeRuntime()
      let root = FBAXFakeElement.readable("UIApplication")
      root.children = [window("cover", displayID: 42), window("inner", displayID: 71)]
      runtime.applicationElements[123] = root
      FBAXClientProvider.setRuntimeForTesting(runtime)
      let response = FBAccessibilityService.handleRequest([
        "verb": "describe", "pid": 123, "displayID": 71, "snapshotTree": snapshot,
      ])
      XCTAssertEqual(response["ok"] as? Bool, true, "\(response)")
      let tree = try XCTUnwrap(response["tree"] as? [String: Any])
      let children = try XCTUnwrap(tree["XC_kAXXCAttributeChildren"] as? [[String: Any]])
      XCTAssertEqual(children.count, 1)
      XCTAssertEqual(children.first?["XC_kAXXCAttributeLabel"] as? String, "inner")
      XCTAssertEqual((children.first?["XC_kAXXCAttributeFrame"] as? [String: Int])?["Width"], 400)
    }
  }

  func testSemanticTreeUsesWindowIdentityFromTheSameElement() throws {
    let runtime = FBAXFakeRuntime()
    let root = FBAXFakeElement.readable("UIApplication")
    let cover = window("cover", displayID: 42)
    let inner = window("inner", displayID: 71)
    runtime.applicationElements[123] = root
    runtime.translatorResponses = [
      [33: "root"], [8: [cover, inner]],
      [33: "cover"], [:], [33: "inner"], [:],
    ]
    FBAXClientProvider.setRuntimeForTesting(runtime)
    let response = FBAccessibilityService.handleRequest([
      "verb": "describe", "pid": 123, "displayID": 71, "translatorVocabulary": true,
    ])
    XCTAssertEqual(response["ok"] as? Bool, true, "\(response)")
    let tree = try XCTUnwrap(response["tree"] as? [String: Any])
    let children = try XCTUnwrap(tree["XC_kAXXCAttributeChildren"] as? [[String: Any]])
    XCTAssertEqual(children.count, 1)
    XCTAssertEqual(children.first?["XC_kAXXCAttributeLabel"] as? String, "inner")
    XCTAssertEqual(children.first?["XC_kAXXCAttributeWindowDisplayId"] as? Int, 71)
    XCTAssertEqual(runtime.lastReadAttributes, ["XC_kAXXCAttributeWindowDisplayId"])
  }

  func testUnknownWindowMembershipDoesNotBecomeSelectedDisplay() {
    for identity in [nil, 0, true, -1, 1.5, "71"] as [Any?] {
      let runtime = FBAXFakeRuntime()
      let root = FBAXFakeElement.readable("UIApplication")
      root.children = [window("unknown", displayID: identity)]
      runtime.applicationElements[123] = root
      FBAXClientProvider.setRuntimeForTesting(runtime)
      let response = FBAccessibilityService.handleRequest(["verb": "describe", "pid": 123, "displayID": 71])
      XCTAssertEqual(response["ok"] as? Bool, false, "\(response)")
      XCTAssertTrue((response["error"] as? String)?.contains("display identity") == true)
      XCTAssertEqual(response["error_kind"] as? String, "capability_unavailable")
    }
  }

  func testExplicitlyDifferentDescendantIsExcluded() throws {
    let runtime = FBAXFakeRuntime()
    let root = FBAXFakeElement.readable("UIApplication")
    let selected = window("selected", displayID: 71)
    selected.children = [window("remote-other-display", displayID: 42)]
    root.children = [selected]
    runtime.applicationElements[123] = root
    FBAXClientProvider.setRuntimeForTesting(runtime)
    let response = FBAccessibilityService.handleRequest(["verb": "describe", "pid": 123, "displayID": 71])
    let tree = try XCTUnwrap(response["tree"] as? [String: Any])
    let children = try XCTUnwrap(tree["XC_kAXXCAttributeChildren"] as? [[String: Any]])
    XCTAssertEqual((children.first?["XC_kAXXCAttributeChildren"] as? [Any])?.count, 0)
  }

  func testApplicationWithNoSelectedWindowDoesNotReturnAnotherDisplaysFrame() {
    let runtime = FBAXFakeRuntime()
    let root = FBAXFakeElement.readable("UIApplication")
    root.children = [window("other-display", displayID: 42)]
    runtime.applicationElements[123] = root
    FBAXClientProvider.setRuntimeForTesting(runtime)
    let response = FBAccessibilityService.handleRequest(["verb": "describe", "pid": 123, "displayID": 71])
    XCTAssertEqual(response["ok"] as? Bool, false)
    XCTAssertEqual(response["error_kind"] as? String, "application_unavailable")
    XCTAssertNil(response["tree"])
  }

  func testUnscopedReadPreservesAllWindows() throws {
    let runtime = FBAXFakeRuntime()
    let root = FBAXFakeElement.readable("UIApplication")
    root.children = [window("cover", displayID: 42), window("inner", displayID: 71)]
    runtime.applicationElements[123] = root
    FBAXClientProvider.setRuntimeForTesting(runtime)
    let response = FBAccessibilityService.handleRequest(["verb": "describe", "pid": 123])
    let tree = try XCTUnwrap(response["tree"] as? [String: Any])
    XCTAssertEqual((tree["XC_kAXXCAttributeChildren"] as? [Any])?.count, 2)
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

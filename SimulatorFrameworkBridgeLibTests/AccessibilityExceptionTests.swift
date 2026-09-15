/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

final class AccessibilityExceptionTests: XCTestCase {
  override func tearDown() {
    FBAXBridgeSetRuntimeForTesting(nil)
    super.tearDown()
  }

  func testEveryRuntimeExceptionStopsTheRequestAndAllowsTheNextRequest() {
    let describe: [String: Any] = ["verb": "describe", "pid": 4321]
    let snapshot: [String: Any] = [
      "verb": "describe", "pid": 4321, "snapshotTree": true,
      "attributes": ["XC_kAXXCAttributeLabel", "XC_kAXXCAttributeFrame", "XC_kAXXCAttributeVisiblePoint"],
    ]
    let cases: [(String, [String: Any])] = [
      ("applicationElement", describe),
      ("readAttributes", describe),
      ("snapshot", snapshot),
      ("snapshotOwner", snapshot),
      ("snapshotContinuation", snapshot),
      ("getRect", snapshot),
      ("getPoint", snapshot),
      ("hitTest", ["verb": "hittest", "x": 1, "y": 2]),
      ("performAction", ["verb": "perform", "x": 1, "y": 2, "action": "press"]),
      ("setValue", ["verb": "setvalue", "x": 1, "y": 2, "value": "changed"]),
      ("windowServerFrontmost", ["verb": "describe", "x": 1, "y": 2, "method": "window-server"]),
      ("runningBoardFrontmost", ["verb": "describe", "x": 1, "y": 2, "method": "runningboard"]),
      ("translatorAttributes", ["verb": "describe", "pid": 4321, "translatorVocabulary": true]),
      ("automationRead", describe),
      ("automationWrite", ["verb": "describe", "pid": 4321, "automationMode": true]),
      ("settingRead", ["verb": "settings-get", "setting": "reduce-motion"]),
      ("settingWrite", ["verb": "settings-set", "setting": "reduce-motion", "enabled": true]),
    ]
    for (operation, request) in cases {
      let runtime = seededRuntime()
      FBAXBridgeSetRuntimeForTesting(runtime)
      runtime.raiseOnOperation = operation

      XCTAssertEqual(FBAXBridgeHandleRequest(request) as NSDictionary, exceptionResponse("injected \(operation)"), operation)
      XCTAssertEqual(runtime.operations.lastObject as? String, operation)

      runtime.raiseOnOperation = nil
      XCTAssertEqual(FBAXBridgeHandleRequest(request)["ok"] as? NSNumber, true, operation)
    }
  }

  func testChildExceptionAbortsTheWholeTreeAndNextReadRecovers() {
    let runtime = seededRuntime()
    let root = runtime.applicationElements[4321] as? FBAXFakeElement
    let child = root?.children.first
    child?.readRaiseReason = "child disappeared"
    FBAXBridgeSetRuntimeForTesting(runtime)
    let request: [String: Any] = ["verb": "describe", "pid": 4321]

    XCTAssertEqual(FBAXBridgeHandleRequest(request) as NSDictionary, exceptionResponse("child disappeared"))
    XCTAssertEqual(runtime.operations.lastObject as? String, "readAttributes")

    child?.readRaiseReason = nil
    let response = FBAXBridgeHandleRequest(request)
    XCTAssertEqual(response["ok"] as? NSNumber, true)
    let tree = response["tree"] as? [String: Any]
    let children = tree?["XC_kAXXCAttributeChildren"] as? [[String: Any]]
    XCTAssertEqual(children?.first?["XC_kAXXCAttributeLabel"] as? String, "child")
  }

  func testAssertionReadExceptionPreventsBothKindsOfWrite() {
    for verb in ["perform", "setvalue"] {
      let runtime = seededRuntime()
      runtime.raiseOnOperation = "readAttributes"
      FBAXBridgeSetRuntimeForTesting(runtime)
      let request: [String: Any] = [
        "verb": verb, "x": 1, "y": 2, "action": "press", "value": "changed",
        "assertKey": "XC_kAXXCAttributeLabel", "assertValue": "root",
      ]

      XCTAssertEqual(FBAXBridgeHandleRequest(request) as NSDictionary, exceptionResponse("injected readAttributes"))
      XCTAssertEqual(runtime.hitTestCount, 1)
      XCTAssertEqual(runtime.performCount, 0)
      XCTAssertEqual(runtime.setValueCount, 0)
      XCTAssertEqual(runtime.operations as NSArray, ["hitTest", "readAttributes"] as NSArray)
    }
  }

  private func exceptionResponse(_ reason: String) -> NSDictionary {
    ["ok": false, "error": "the reader raised while answering: \(reason)"]
  }

  private func seededRuntime() -> FBAXFakeRuntime {
    let runtime = FBAXFakeRuntime()
    let root = FBAXFakeElement.readable("root")
    root.owningProcessIdentifier = 4321
    root.attributes = [
      "XC_kAXXCAttributeLabel": "root",
      "XC_kAXXCAttributeFrame": FBAXFakeRectValue.withRect(CGRect(x: 1, y: 2, width: 3, height: 4)),
      "XC_kAXXCAttributeVisiblePoint": FBAXFakePointValue.withPoint(CGPoint(x: 2, y: 3)),
    ]
    let child = FBAXFakeElement.readable("child")
    child.owningProcessIdentifier = 8765
    let grandchild = FBAXFakeElement.readable("grandchild")
    grandchild.owningProcessIdentifier = 8765
    child.children = [grandchild]
    root.children = [child]
    runtime.applicationElements[4321] = root
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(root, owningProcessIdentifier: 4321)
    runtime.windowServerOutcome = FBAXFrontmostOutcome.resolved(4321)
    runtime.runningBoardOutcome = FBAXFrontmostOutcome.resolved(4321)
    runtime.translatorAttributeValues = [NSNumber(value: FBAXPAttribute.attributeLabel.rawValue): "root"]
    runtime.deviceSettings[NSNumber(value: FBAXDeviceSetting.reduceMotion.rawValue)] = false
    return runtime
  }
}

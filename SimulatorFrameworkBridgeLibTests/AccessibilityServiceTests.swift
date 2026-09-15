/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

final class AccessibilityServiceTests: XCTestCase {

  private static func FBAXTestsFrameResponse(rect: CGRect) -> [String: Any] {
    let frame = rect.dictionaryRepresentation as NSDictionary
    return ["ok": true, "tree": ["XC_kAXXCAttributeLabel": "icon", "XC_kAXXCAttributeFrame": frame]]
  }

  private static func FBAXTestsParse(data: Data) -> NSDictionary? {
    (try? JSONSerialization.jsonObject(with: data)) as? NSDictionary
  }

  // `NSJSONSerialization` raises on a non-finite number rather than returning an error, which would abort
  // the reader mid-read.
  func testInfiniteFrameValueSerializesAsNull() {
    let data = FBAXBridgeSerializeResponse(Self.FBAXTestsFrameResponse(rect: CGRect(x: Double.infinity, y: 0, width: 10, height: 20)))
    let parsed = Self.FBAXTestsParse(data: data)
    XCTAssertNotNil(parsed, "a non-finite frame must still produce parseable JSON")
    XCTAssertEqual(parsed?["ok"] as? NSNumber, NSNumber(value: true))

    let frame = (parsed?["tree"] as? NSDictionary)?["XC_kAXXCAttributeFrame"] as? NSDictionary
    XCTAssertEqual(frame?["X"] as? NSNull, NSNull(), "the non-finite member must be null")
    XCTAssertEqual(frame?["Height"] as? NSNumber, 20, "finite members must be preserved")
    XCTAssertEqual(
      (parsed?["tree"] as? NSDictionary)?["XC_kAXXCAttributeLabel"] as? String,
      "icon",
      "the rest of the node must survive"
    )
  }

  func testFiniteResponseIsUnchanged() {
    let data = FBAXBridgeSerializeResponse(Self.FBAXTestsFrameResponse(rect: CGRect(x: 16, y: 293, width: 370, height: 52)))
    let frame = (Self.FBAXTestsParse(data: data)?["tree"] as? NSDictionary)?["XC_kAXXCAttributeFrame"] as? NSDictionary
    XCTAssertEqual(frame?["X"] as? NSNumber, 16)
    XCTAssertEqual(frame?["Y"] as? NSNumber, 293)
    XCTAssertEqual(frame?["Width"] as? NSNumber, 370)
    XCTAssertEqual(frame?["Height"] as? NSNumber, 52)
  }

  func testUnserializableValueYieldsAnErrorFrameRatherThanRaising() {
    let response: [String: Any] = ["ok": true, "tree": Date()]
    let parsed = Self.FBAXTestsParse(data: FBAXBridgeSerializeResponse(response))
    XCTAssertEqual(parsed?["ok"] as? NSNumber, NSNumber(value: false))
    XCTAssertNotNil(parsed?["error"])
  }

  // MARK: - Request validation

  func testNonStringVerbIsRejectedWithAnErrorFrame() {
    for verb in [123, ["a": 1], ["describe"], NSNull()] as [Any] {
      let response = FBAXBridgeHandleRequest(["verb": verb])
      XCTAssertEqual(response["ok"] as? NSNumber, NSNumber(value: false), "a \(type(of: verb)) verb must be rejected")
      XCTAssertNotNil(response["error"] as? String, "a \(type(of: verb)) verb must carry an error message")
      XCTAssertEqual(response["error_kind"] as? String, "bad_request", "a \(type(of: verb)) verb")
    }
  }

  func testShutdownIsAnsweredWithoutARuntimeOrAPid() {
    FBAXBridgeSetRuntimeForTesting(nil)
    let response = FBAXBridgeHandleRequest(["verb": "shutdown"])
    XCTAssertEqual(response["ok"] as? NSNumber, NSNumber(value: true))
    XCTAssertEqual(response["shutdown"] as? NSNumber, NSNumber(value: true))
    XCTAssertNil(response["error"])
  }

  // A caller reaping an orphan has no pid in mind; refusing would make the orphan unreapable.
  func testShutdownIgnoresAnUnusablePid() {
    let response = FBAXBridgeHandleRequest(["verb": "shutdown", "pid": 0])
    XCTAssertEqual(response["ok"] as? NSNumber, NSNumber(value: true))
    XCTAssertEqual(response["shutdown"] as? NSNumber, NSNumber(value: true))
  }

  // `nil` takes `isEqualToString:` without complaint and matches no verb.
  func testMissingVerbIsRejectedWithAnErrorFrame() {
    let response = FBAXBridgeHandleRequest(["pid": 1234])
    XCTAssertEqual(response["ok"] as? NSNumber, NSNumber(value: false))
    XCTAssertEqual(response["error"] as? String, "unsupported verb: (nil)")
    XCTAssertEqual(response["error_kind"] as? String, "bad_request")
  }

  // The host maps `application_unavailable` onto a typed error, so a pid that names no process must carry
  // that kind on every verb.
  func testNonPositivePidIsReportedAsAnUnavailableApplication() {
    let requests: [[String: Any]] = [["verb": "describe", "pid": 0], ["verb": "describe", "pid": (-1) as NSNumber], ["verb": "hittest", "pid": 0, "x": 200, "y": 400], ["verb": "hittest", "pid": (-1) as NSNumber, "x": 200, "y": 400], ["verb": "perform", "pid": 0, "x": 200, "y": 400, "action": "press"], ["verb": "perform", "pid": (-1) as NSNumber, "x": 200, "y": 400, "action": "press"], ["verb": "setvalue", "pid": 0, "x": 200, "y": 400, "value": "hello"], ["verb": "setvalue", "pid": (-1) as NSNumber, "x": 200, "y": 400, "value": "hello"]]
    for request in requests {
      let response = FBAXBridgeHandleRequest(request)
      XCTAssertEqual(response["ok"] as? NSNumber, NSNumber(value: false), String(describing: request))
      XCTAssertEqual(
        response["error_kind"] as? String,
        "application_unavailable",
        String(describing: request)
      )
      XCTAssertEqual(response["pid"] as? NSNumber, request["pid"] as? NSNumber, "the rejected pid must be named back")
    }
  }

  // MARK: - Wire contract

  // Guest and host share no header for these strings. This pins the guest's constants to the literals the
  // host pins in `AXWireContractTests`; the two files agreeing is the contract.
  func testGuestWireConstantsMatchTheHostContract() {
    let expected = [
      "node.elementType": "XC_kAXXCAttributeElementType", "node.elementBaseType": "XC_kAXXCAttributeElementBaseType", "node.label": "XC_kAXXCAttributeLabel", "node.value": "XC_kAXXCAttributeValue", "node.identifier": "XC_kAXXCAttributeIdentifier", "node.frame": "XC_kAXXCAttributeFrame", "node.automationType": "XC_kAXXCAttributeAutomationType", "node.children": "XC_kAXXCAttributeChildren", "request.verb": "verb", "request.pid": "pid", "request.maxDepth": "maxDepth", "request.maxNodes": "maxNodes", "request.automationMode": "automationMode", "request.attributes": "attributes", "request.translatorVocabulary": "translatorVocabulary", "request.explainUnreachable": "explainUnreachable", "node.explainedBy": "FBExplainedBy", "node.isEnabled": "FBIsEnabled", "node.translatorRole": "FBTranslatorRole", "node.translatorSubrole": "FBTranslatorSubrole", "node.traits": "FBTraits", "node.elementIdentity": "FBElementIdentity", "request.x": "x", "request.y": "y", "request.method": "method", "request.action": "action", "request.value": "value", "request.setting": "setting", "request.enabled": "enabled", "request.assertKey": "assertKey", "request.assertValue": "assertValue", "envelope.ok": "ok", "envelope.enabled": "enabled", "envelope.tree": "tree", "envelope.error": "error", "envelope.empty": "empty", "envelope.errorKind": "error_kind", "envelope.errorKindApplicationUnavailable": "application_unavailable", "envelope.errorKindApplicationNotResponding": "application_not_responding", "envelope.errorKindFrontmostUnresolved": "frontmost_unresolved", "envelope.errorKindReaderUnavailable": "reader_unavailable", "envelope.errorKindBadRequest": "bad_request", "envelope.errorKindAssertionFailed": "assertion_failed", "envelope.truncated": "truncated", "envelope.pid": "pid", "envelope.method": "method", "envelope.modal": "modal", "envelope.automation": "automation", "envelope.phases": "phases", "phases.traverse": "traverse_ms", "phases.machRoundTrips": "mach_round_trips",
      "automation.enabled": "enabled", "automation.asserted": "asserted", "modal.kind": "kind", "modal.kindSystem": "system", "modal.kindApp": "app", "modal.elementType": "elementType", "modal.label": "label", "modal.systemAlertWindowClass": "SBAlertItemWindow", "modal.alertControllerClassPrefix": "_UIAlertController", "verb.describe": "describe", "verb.hittest": "hittest", "verb.perform": "perform", "verb.setvalue": "setvalue", "verb.settingsGet": "settings-get", "verb.settingsSet": "settings-set", "verb.shutdown": "shutdown", "action.press": "press", "action.scrollUp": "scroll-up", "action.scrollDown": "scroll-down", "action.scrollLeft": "scroll-left", "action.scrollRight": "scroll-right", "action.scrollToVisible": "scroll-to-visible", "method.centerPoint": "center-point", "method.windowServer": "window-server", "method.runningBoard": "runningboard",
    ]
    // Whole-dictionary equality also fails on any guest constant this test forgot to pin (or any removed),
    // not just a changed value.
    XCTAssertEqual(FBAXBridgeWireConstantsForTesting(), expected)
  }

  // MARK: - Modal detection

  func testModalDescriptorReportsSystemAlertWindowAsSystemKind() {
    let tree: [String: Any] = ["XC_kAXXCAttributeLabel": "root", "XC_kAXXCAttributeChildren": [["XC_kAXXCAttributeElementType": "SBAlertItemWindow"]]]
    let modal = FBAXBridgeModalDescriptor(tree)
    XCTAssertEqual(modal?["kind"] as? String, "system")
    XCTAssertEqual(modal?["elementType"] as? String, "SBAlertItemWindow")
    XCTAssertNil(modal?["label"] as? String, "a system-only alert carries no captured label")
  }

  // `_UIAlertController*` is matched by prefix; the concrete class varies.
  func testModalDescriptorReportsAlertControllerAsAppKindWithElementTypeAndLabel() {
    let tree: [String: Any] = ["XC_kAXXCAttributeLabel": "root", "XC_kAXXCAttributeChildren": [["XC_kAXXCAttributeElementType": "_UIAlertControllerView", "XC_kAXXCAttributeLabel": "Delete this item?"]]]
    let modal = FBAXBridgeModalDescriptor(tree)
    XCTAssertEqual(modal?["kind"] as? String, "app")
    XCTAssertEqual(modal?["elementType"] as? String, "_UIAlertControllerView")
    XCTAssertEqual(modal?["label"] as? String, "Delete this item?")
  }

  func testModalDescriptorPrefersSystemKindWhenBothAlertsPresent() {
    let tree: [String: Any] = ["XC_kAXXCAttributeLabel": "root", "XC_kAXXCAttributeChildren": [["XC_kAXXCAttributeElementType": "SBAlertItemWindow"], ["XC_kAXXCAttributeElementType": "_UIAlertControllerView", "XC_kAXXCAttributeLabel": "Allow"]]]
    let modal = FBAXBridgeModalDescriptor(tree)
    XCTAssertEqual(modal?["kind"] as? String, "system", "a system alert window wins over an app alert")
    XCTAssertEqual(
      modal?["elementType"] as? String,
      "_UIAlertControllerView",
      "the captured alert-controller class is still reported"
    )
    XCTAssertEqual(modal?["label"] as? String, "Allow")
  }

  func testModalDescriptorReturnsNilWhenNoAlertPresent() {
    let tree: [String: Any] = ["XC_kAXXCAttributeLabel": "root", "XC_kAXXCAttributeChildren": [["XC_kAXXCAttributeElementType": "XCUIElementTypeButton", "XC_kAXXCAttributeLabel": "OK"]]]
    XCTAssertNil(FBAXBridgeModalDescriptor(tree))
  }
}

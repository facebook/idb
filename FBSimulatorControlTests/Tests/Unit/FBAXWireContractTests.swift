/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// Byte-level pins for the host side of the axbridge wire contract: the `XC_kAXXC*` node-attribute
/// keys the read path fetches, the output-schema keys (`FBAXKeys`), and the frontmost-method request
/// selectors. These strings cross the guest↔host boundary with no shared header, so a rename here is a
/// silent protocol break; pinning them exactly is what makes the later single-sourcing (folding the
/// scattered literals into `FBAXWire`) provably byte-preserving. The guest-side agreement is pinned
/// against these same literals in the `SimulatorFrameworkBridge` tests.
final class FBAXWireContractTests: XCTestCase {

  // MARK: - Node-attribute keys (the `_XCTD_fetchAttributes:` request/echo keys)

  func testNodeAttributeWireKeys() {
    XCTAssertEqual(FBRemoteAutomationAXAttribute.elementType, "XC_kAXXCAttributeElementType")
    XCTAssertEqual(FBRemoteAutomationAXAttribute.elementBaseType, "XC_kAXXCAttributeElementBaseType")
    XCTAssertEqual(FBRemoteAutomationAXAttribute.label, "XC_kAXXCAttributeLabel")
    XCTAssertEqual(FBRemoteAutomationAXAttribute.value, "XC_kAXXCAttributeValue")
    XCTAssertEqual(FBRemoteAutomationAXAttribute.identifier, "XC_kAXXCAttributeIdentifier")
    XCTAssertEqual(FBRemoteAutomationAXAttribute.frame, "XC_kAXXCAttributeFrame")
    XCTAssertEqual(FBRemoteAutomationAXAttribute.automationType, "XC_kAXXCAttributeAutomationType")
    XCTAssertEqual(FBRemoteAutomationAXAttribute.children, "XC_kAXXCAttributeChildren")
  }

  // The read requests exactly this ordered set — the guest fetches and echoes back these keys, so both
  // the membership and the order are part of the contract.
  func testFetchListIsTheOrderedReadAttributeSet() {
    XCTAssertEqual(
      FBRemoteAutomationAXAttribute.fetchList,
      [
        "XC_kAXXCAttributeElementType",
        "XC_kAXXCAttributeElementBaseType",
        "XC_kAXXCAttributeLabel",
        "XC_kAXXCAttributeValue",
        "XC_kAXXCAttributeIdentifier",
        "XC_kAXXCAttributeFrame",
        "XC_kAXXCAttributeAutomationType",
        "XC_kAXXCAttributeChildren",
      ]
    )
  }

  // MARK: - Output-schema keys (`FBAXKeys` raw values are the emitted JSON keys)

  func testAXKeyWireValues() {
    let expected: [FBAXKeys: String] = [
      .label: "AXLabel",
      .frame: "AXFrame",
      .value: "AXValue",
      .uniqueID: "AXUniqueId",
      .type: "type",
      .title: "title",
      .frameDict: "frame",
      .help: "help",
      .enabled: "enabled",
      .customActions: "custom_actions",
      .role: "role",
      .roleDescription: "role_description",
      .subrole: "subrole",
      .contentRequired: "content_required",
      .pid: "pid",
      .traits: "traits",
      .expanded: "expanded",
      .placeholder: "placeholder",
      .hidden: "hidden",
      .focused: "focused",
      .isRemote: "is_remote",
    ]
    XCTAssertEqual(expected.count, 21, "every FBAXKeys case must have its wire value pinned")
    for (key, wireValue) in expected {
      XCTAssertEqual(key.rawValue, wireValue, "\(key) must serialize under its pinned wire key")
    }
  }

  // The default set is the schema emitted when no keys are requested; it must stay exactly these 16,
  // with the 5 opt-in keys (`expanded`/`placeholder`/`hidden`/`focused`/`is_remote`) out of it.
  func testDefaultKeySetMembership() {
    XCTAssertEqual(
      FBAXKeys.defaultSet,
      [
        .label, .frame, .value, .uniqueID, .type, .title, .frameDict, .help,
        .enabled, .customActions, .role, .roleDescription, .subrole,
        .contentRequired, .pid, .traits,
      ]
    )
    XCTAssertEqual(FBAXKeys.defaultSet.count, 16)
    let optIn: Set<FBAXKeys> = [.expanded, .placeholder, .hidden, .focused, .isRemote]
    XCTAssertTrue(FBAXKeys.defaultSet.isDisjoint(with: optIn), "the opt-in keys must stay out of the default set")
  }

  // MARK: - Frontmost-method request selectors

  // `FBAXBridgeFrontmostMethod`'s raw values are the selectors the host sends the guest to pick a
  // frontmost-resolution strategy; each must round-trip through its raw value. Once the guest response
  // spelling is unified, the guest-reported `method` decodes back into these same cases.
  func testFrontmostMethodRequestSelectors() {
    let expected: [FBAXBridgeFrontmostMethod: String] = [
      .centerPoint: "center-point",
      .windowServer: "window-server",
      .runningBoard: "runningboard",
    ]
    XCTAssertEqual(
      Set(FBAXBridgeFrontmostMethod.allCases), Set(expected.keys),
      "every frontmost method must have its selector pinned"
    )
    for (method, selector) in expected {
      XCTAssertEqual(method.rawValue, selector)
      XCTAssertEqual(FBAXBridgeFrontmostMethod(rawValue: selector), method, "\(method) must round-trip through its selector")
    }
  }
}

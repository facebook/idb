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
    XCTAssertEqual(FBAXWire.Node.elementType.rawValue, "XC_kAXXCAttributeElementType")
    XCTAssertEqual(FBAXWire.Node.elementBaseType.rawValue, "XC_kAXXCAttributeElementBaseType")
    XCTAssertEqual(FBAXWire.Node.label.rawValue, "XC_kAXXCAttributeLabel")
    XCTAssertEqual(FBAXWire.Node.value.rawValue, "XC_kAXXCAttributeValue")
    XCTAssertEqual(FBAXWire.Node.identifier.rawValue, "XC_kAXXCAttributeIdentifier")
    XCTAssertEqual(FBAXWire.Node.frame.rawValue, "XC_kAXXCAttributeFrame")
    XCTAssertEqual(FBAXWire.Node.automationType.rawValue, "XC_kAXXCAttributeAutomationType")
    XCTAssertEqual(FBAXWire.Node.children.rawValue, "XC_kAXXCAttributeChildren")
  }

  // The read requests exactly this ordered set — the guest fetches and echoes back these keys, so both
  // the membership and the order are part of the contract.
  func testFetchListIsTheOrderedReadAttributeSet() {
    XCTAssertEqual(
      FBAXWire.Node.fetchList,
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

  // MARK: - Failure kinds

  // `error_kind` is how the host decides what a failure *was* without matching on the guest's free-text
  // message, so each spelling is as much a part of the contract as a node key. Pinned over `allCases`, so
  // a kind added host-side without a guest that emits it fails here rather than silently never matching.
  func testFailureKindWireValues() {
    let expected: [FBAXWire.ErrorKind: String] = [
      .applicationUnavailable: "application_unavailable",
      .applicationNotResponding: "application_not_responding",
      .frontmostUnresolved: "frontmost_unresolved",
      .readerUnavailable: "reader_unavailable",
      .badRequest: "bad_request",
    ]
    XCTAssertEqual(Set(FBAXWire.ErrorKind.allCases), Set(expected.keys), "every failure kind must have its wire value pinned")
    for (kind, wireValue) in expected {
      XCTAssertEqual(kind.rawValue, wireValue)
      XCTAssertEqual(FBAXWire.ErrorKind(rawValue: wireValue), kind, "\(kind) must round-trip through its wire value")
    }
  }

  // A kind this host has never heard of has to parse as "no kind" — an opaque reader failure — rather
  // than as anything the host would act on. That is what lets the guest gain a kind ahead of the host it
  // is talking to and cost only precision.
  func testAnUnknownFailureKindIsNotAKnownOne() {
    XCTAssertNil(FBAXWire.ErrorKind(rawValue: "application_on_fire"))
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

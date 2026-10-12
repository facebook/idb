/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation
import XCTest

final class BridgeAXResponseTests: XCTestCase {
  func testADisplayInventoryDecodesFromThePayloadTheGuestSends() throws {
    let inventory = BridgeAXDisplayInventory(
      displayScopedInteractions: true,
      displayScopedTrees: false,
      displayScopedQuiescence: true,
      displays: [.init(uniqueID: "main", displayID: 1), .init(uniqueID: "external", displayID: 7)]
    )
    let data = try JSONSerialization.data(withJSONObject: inventory.payload)
    XCTAssertEqual(try JSONDecoder().decode(BridgeAXDisplayInventory.self, from: data), inventory)
  }

  func testADisplayInventoryKeepsItsWireSpelling() throws {
    let payload = BridgeAXDisplayInventory(
      displayScopedInteractions: true, displayScopedTrees: true, displayScopedQuiescence: true,
      displays: [.init(uniqueID: "main", displayID: 1)]
    ).payload
    XCTAssertEqual(
      Set(payload.keys), ["displayScopedInteractions", "displayScopedTrees", "displayScopedQuiescence", "displays"])
    let display = try XCTUnwrap((payload["displays"] as? [[String: Any]])?.first)
    XCTAssertEqual(Set(display.keys), ["uniqueID", "displayID"])
  }

  func testACapabilityTheInventoryDoesNotMentionIsNotAdvertised() throws {
    let data = Data(#"{"displays":[{"uniqueID":"main","displayID":1}]}"#.utf8)
    let inventory = try JSONDecoder().decode(BridgeAXDisplayInventory.self, from: data)
    XCTAssertFalse(inventory.displayScopedInteractions || inventory.displayScopedTrees || inventory.displayScopedQuiescence)
    XCTAssertEqual(inventory.displays, [.init(uniqueID: "main", displayID: 1)])
  }

  func testAModalDecodesFromThePayloadTheGuestSends() {
    for modal in [
      BridgeAXModal(kind: .system, elementType: "SBAlertItemWindow", label: nil),
      BridgeAXModal(kind: .app, elementType: "_UIAlertControllerPhoneTVMacView", label: "Allow?"),
    ] {
      XCTAssertEqual(BridgeAXModal(payload: modal.payload), modal)
    }
  }

  func testAModalKeepsItsWireSpellingAndRefusesAnUnknownKind() {
    XCTAssertEqual(
      BridgeAXModal(kind: .app, elementType: "Alert", label: "Title").payload,
      ["kind": "app", "elementType": "Alert", "label": "Title"])
    XCTAssertNil(BridgeAXModal(payload: ["kind": "dialog", "elementType": "Alert"]))
    XCTAssertNil(BridgeAXModal(payload: ["kind": "app"]))
  }
}

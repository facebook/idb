/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation
import Testing

@Suite
struct BridgeAXResponseTests {
  @Test
  func aDisplayInventoryDecodesFromThePayloadTheGuestSends() throws {
    let inventory = BridgeAXDisplayInventory(
      displayScopedInteractions: true,
      displayScopedTrees: false,
      displayScopedQuiescence: true,
      displays: [.init(uniqueID: "main", displayID: 1), .init(uniqueID: "external", displayID: 7)]
    )
    let data = try JSONSerialization.data(withJSONObject: inventory.payload)
    #expect(try JSONDecoder().decode(BridgeAXDisplayInventory.self, from: data) == inventory)
  }

  @Test
  func aDisplayInventoryKeepsItsWireSpelling() throws {
    let payload = BridgeAXDisplayInventory(
      displayScopedInteractions: true, displayScopedTrees: true, displayScopedQuiescence: true,
      displays: [.init(uniqueID: "main", displayID: 1)]
    ).payload
    #expect(
      Set(payload.keys) == ["displayScopedInteractions", "displayScopedTrees", "displayScopedQuiescence", "displays"])
    let display = try #require((payload["displays"] as? [[String: Any]])?.first)
    #expect(Set(display.keys) == ["uniqueID", "displayID"])
  }

  @Test
  func aModalDecodesFromThePayloadTheGuestSends() {
    for modal in [
      BridgeAXModal(kind: .system, elementType: "SBAlertItemWindow", label: nil),
      BridgeAXModal(kind: .app, elementType: "_UIAlertControllerPhoneTVMacView", label: "Allow?"),
    ] {
      #expect(BridgeAXModal(payload: modal.payload) == modal)
    }
  }

  @Test
  func aModalKeepsItsWireSpellingAndRefusesAnUnknownKind() {
    #expect(
      BridgeAXModal(kind: .app, elementType: "Alert", label: "Title").payload == ["kind": "app", "elementType": "Alert", "label": "Title"])
    #expect(BridgeAXModal(payload: ["kind": "dialog", "elementType": "Alert"]) == nil)
    #expect(BridgeAXModal(payload: ["kind": "app"]) == nil)
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import XCTest

private actor InventoryTransport: AXBridgeTransport {
  private let inventory: [SimulatorAccessibilityDisplay]
  private(set) var sends = 0

  init(_ inventory: [SimulatorAccessibilityDisplay]) {
    self.inventory = inventory
  }

  func send(_ request: AXBridgeRequest) async throws -> Data {
    sends += 1
    let displays = inventory.map { ["uniqueID": $0.uniqueID, "displayID": $0.displayID] as [String: Any] }
    return try JSONSerialization.data(withJSONObject: ["ok": true, "displays": displays])
  }
}

final class DisplayCommandsTests: XCTestCase {
  private func display(_ id: String, width: Double = 1200) -> SimulatorDisplay {
    SimulatorDisplay(
      uniqueID: id, name: id, isActive: true, isPrimary: false, isIntegrated: true,
      bounds: CGRect(x: 0, y: 0, width: width, height: 800), scale: 2, rotation: .upright)
  }

  private let inventory = [
    SimulatorAccessibilityDisplay(uniqueID: "cover", displayID: 2),
    SimulatorAccessibilityDisplay(uniqueID: "inner", displayID: 3),
  ]

  func testSoleDisplayIsReachedUnscopedWithoutAskingTheGuest() async throws {
    let displays = DisplayCommandsDouble(.sole(.identified(display("lcd"))))
    let transport = InventoryTransport(inventory)
    let resolved = try await displays.accessibilityDisplay(transport: transport)
    XCTAssertEqual(resolved, AXTranslationDisplay(display: .identified(display("lcd")), accessibilityID: nil))
    XCTAssertEqual(displays.reads, 1)
    let sends = await transport.sends
    XCTAssertEqual(sends, 0)
  }

  func testSelectedDisplayIdentityIsLookedUpOnceAndConfirmed() async throws {
    let displays = DisplayCommandsDouble(.selected(display("inner")))
    let transport = InventoryTransport(inventory)
    let first = try await displays.accessibilityDisplay(transport: transport)
    XCTAssertEqual(first?.accessibilityID, 3)
    XCTAssertEqual(displays.reads, 2)
    let second = try await displays.accessibilityDisplay(transport: transport)
    XCTAssertEqual(second, first)
    XCTAssertEqual(displays.reads, 3)
    let sends = await transport.sends
    XCTAssertEqual(sends, 1)
  }

  func testNewlySelectedDisplayRefreshesTheCache() async throws {
    let displays = DisplayCommandsDouble(.selected(display("inner")), .selected(display("inner")), .selected(display("cover")))
    let transport = InventoryTransport(inventory)
    let inner = try await displays.accessibilityDisplay(transport: transport)
    let cover = try await displays.accessibilityDisplay(transport: transport)
    XCTAssertEqual(inner?.accessibilityID, 3)
    XCTAssertEqual(cover?.accessibilityID, 2)
    let sends = await transport.sends
    XCTAssertEqual(sends, 1)
  }

  func testUnlistedDisplayHasNoMapping() async throws {
    let displays = DisplayCommandsDouble(.selected(display("rear")))
    do {
      _ = try await displays.accessibilityDisplay(transport: InventoryTransport(inventory))
      XCTFail("Expected a missing mapping")
    } catch SimulatorDisplayInteractionError.missingMapping("rear") {}
    XCTAssertNil(displays.identities.accessibilityID(for: "inner"))
  }

  func testDisplayChangeDuringLookupFails() async throws {
    let displays = DisplayCommandsDouble(.selected(display("inner")), .selected(display("cover")))
    do {
      _ = try await displays.accessibilityDisplay(transport: InventoryTransport(inventory))
      XCTFail("Expected a display change")
    } catch SimulatorDisplayError.changed {}
    XCTAssertNil(displays.identities.accessibilityID(for: "inner"))
  }

  func testRuntimeWithoutDisplayReportsRoutesNothing() async throws {
    let displays = DisplayCommandsDouble([.failure(SimulatorCoreDeviceError.unsupported("displayinfo"))])
    let resolved = try await displays.accessibilityDisplay(transport: InventoryTransport(inventory))
    XCTAssertNil(resolved)
  }

  func testValidateComparesConfiguration() async throws {
    let displays = DisplayCommandsDouble(.selected(display("inner")))
    try await displays.validate(.identified(display("inner")))
    do {
      try await displays.validate(.identified(display("inner", width: 800)))
      XCTFail("Expected a display change")
    } catch SimulatorDisplayError.changed {}
  }
}

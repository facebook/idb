/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import XCTest

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

  func testRequiredCapabilityIsCheckedOnlyWhenTheDisplayMustBeNamed() async throws {
    let sole = DisplayCommandsDouble(.sole(.identified(display("lcd"))))
    let soleTransport = InventoryTransport(inventory)
    _ = try await sole.accessibilityDisplay(transport: soleTransport, requiring: .scopedInteractions)
    let soleSends = await soleTransport.sends
    XCTAssertEqual(soleSends, 0)

    let selected = DisplayCommandsDouble(.selected(display("inner")))
    selected.identities.remember(inventory)
    let oldGuest = InventoryTransport(inventory)
    do {
      _ = try await selected.accessibilityDisplay(transport: oldGuest, requiring: .scopedInteractions)
      XCTFail("Expected the guest to lack scoped interactions")
    } catch SimulatorDisplayInteractionError.unsupportedCapability {}
    let oldGuestSends = await oldGuest.sends
    XCTAssertEqual(oldGuestSends, 1)

    let currentGuest = InventoryTransport(inventory, scopedInteractions: true)
    for _ in 0..<2 {
      let resolved = try await selected.accessibilityDisplay(transport: currentGuest, requiring: .scopedInteractions)
      XCTAssertEqual(resolved?.accessibilityID, 3)
    }
    let currentGuestSends = await currentGuest.sends
    XCTAssertEqual(currentGuestSends, 1)
  }

  func testLookupDuringADisplayTransitionSettlesOnTheNextReport() async throws {
    let settled = Result<SimulatorDisplayTarget, any Error>.success(.selected(display("inner")))
    let touchscreens = [SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: 29)]
    let accessibility = DisplayCommandsDouble([transition, settled])
    let hid = DisplayCommandsDouble([transition, settled], touchscreens: touchscreens)
    let context = DisplayCommandsDouble([transition, settled], touchscreens: touchscreens)
    let transport = InventoryTransport(inventory)
    let accessibilityID = await outcome { try await accessibility.accessibilityDisplay(transport: transport)?.accessibilityID }
    let digitizerTarget = await outcome { try await hid.hidDisplay()?.digitizerTarget }
    let contextTarget = await outcome { try await context.interactionContext(for: nil, transport: transport).digitizerTarget }
    // BUG: each lookup fails on the transitional report instead of reading again — flipped in the following commit.
    assertTransitioning(accessibilityID)
    assertTransitioning(digitizerTarget)
    assertTransitioning(contextTarget)
    XCTAssertEqual([accessibility.reads, hid.reads, context.reads], [1, 1, 1])
  }

  func testLookupFailsWhenADisplayTransitionDoesNotSettle() async {
    let displays = DisplayCommandsDouble([transition])
    assertTransitioning(await outcome { try await displays.hidDisplay() })
    // BUG: gives up on the first transitional report — flipped in the following commit.
    XCTAssertEqual(displays.reads, 1)
  }

  private let transition = Result<SimulatorDisplayTarget, any Error>.failure(SimulatorDisplayError.transitioning)

  private func outcome<T>(_ body: () async throws -> T) async -> Result<T, any Error> {
    do { return .success(try await body()) } catch { return .failure(error) }
  }

  private func assertTransitioning<T>(_ result: Result<T, any Error>, file: StaticString = #filePath, line: UInt = #line) {
    guard case let .failure(error) = result, case SimulatorDisplayError.transitioning = error else {
      return XCTFail("\(result)", file: file, line: line)
    }
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

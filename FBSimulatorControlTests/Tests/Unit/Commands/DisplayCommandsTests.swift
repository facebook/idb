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

final class DisplayCommandsTests: XCTestCase {
  private func display(_ id: String, width: Double = 1200) -> SimulatorDisplay {
    SimulatorDisplay(
      uniqueID: id, name: id, activity: .active, isPrimary: false, isIntegrated: true,
      bounds: CGRect(x: 0, y: 0, width: width, height: 800), scale: 2, rotation: .upright)
  }

  private let inventory = [
    SimulatorAccessibilityDisplay(uniqueID: "cover", displayID: 2),
    SimulatorAccessibilityDisplay(uniqueID: "inner", displayID: 3),
  ]

  func testSoleDisplayResolvesWithoutNamingIt() async throws {
    let displays = DisplayCommandsDouble(.sole(.identified(display("lcd"))))
    let resolved = try await displays.resolveDisplay()
    XCTAssertEqual(resolved, .target(.sole(.identified(display("lcd")))))
    XCTAssertEqual(displays.reads, 1)
  }

  func testSelectedDisplayIdentityIsLookedUpOnceAndConfirmed() async throws {
    let displays = DisplayCommandsDouble(.selected(display("inner")))
    let transport = InventoryTransport(inventory)
    let first = try await displays.accessibilityID(for: display("inner"), transport: transport)
    XCTAssertEqual(first, 3)
    XCTAssertEqual(displays.reads, 1)
    let second = try await displays.accessibilityID(for: display("inner"), transport: transport)
    XCTAssertEqual(second, first)
    XCTAssertEqual(displays.reads, 1)
    let sends = await transport.sends
    XCTAssertEqual(sends, 1)
  }

  func testNewlySelectedDisplayRefreshesTheCache() async throws {
    let displays = DisplayCommandsDouble(.selected(display("inner")), .selected(display("cover")))
    let transport = InventoryTransport(inventory)
    let inner = try await displays.accessibilityID(for: display("inner"), transport: transport)
    let cover = try await displays.accessibilityID(for: display("cover"), transport: transport)
    XCTAssertEqual(inner, 3)
    XCTAssertEqual(cover, 2)
    let sends = await transport.sends
    XCTAssertEqual(sends, 1)
  }

  func testUnlistedDisplayHasNoMapping() async throws {
    let displays = DisplayCommandsDouble(.selected(display("rear")))
    do {
      _ = try await displays.accessibilityID(for: display("rear"), transport: InventoryTransport(inventory))
      XCTFail("Expected a missing mapping")
    } catch SimulatorDisplayInteractionError.missingMapping("rear") {}
    XCTAssertNil(displays.identities.accessibilityID(for: "inner"))
  }

  func testDisplayChangeDuringLookupFails() async throws {
    let displays = DisplayCommandsDouble(.selected(display("cover")))
    do {
      _ = try await displays.accessibilityID(for: display("inner"), transport: InventoryTransport(inventory))
      XCTFail("Expected a display change")
    } catch SimulatorDisplayError.changed {}
    XCTAssertNil(displays.identities.accessibilityID(for: "inner"))
  }

  func testRuntimeWithoutDisplayReportsFallsBack() async throws {
    let displays = DisplayCommandsDouble([.success(.failed(.unsupported("displayinfo")))])
    let resolved = try await displays.resolveDisplay()
    XCTAssertEqual(resolved, .fallback(.unreadable(.unsupported("displayinfo"))))
  }

  func testRuntimeThatCannotSayWhichDisplayIsTargetedFallsBack() async throws {
    let geometry = SimulatorDisplayGeometry(bounds: CGRect(x: 0, y: 0, width: 1200, height: 800), scale: 2, rotation: .upright)
    let cover = display("cover")
    let inactive = SimulatorDisplay(
      uniqueID: "inner", name: "inner", activity: .inactive, isPrimary: false, isIntegrated: true, bounds: cover.bounds, scale: 2,
      rotation: .upright)
    let unknown = SimulatorDisplay(
      uniqueID: "lcd", name: "lcd", activity: .unknown, isPrimary: false, isIntegrated: true, bounds: cover.bounds, scale: 2,
      rotation: .upright)
    let cases: [(SimulatorDisplayReport, SimulatorDisplayFallback)] = [
      (.failed(.unavailable("displayinfo")), .unreadable(.unavailable("displayinfo"))),
      (.failed(.timedOut), .unreadable(.timedOut)),
      (.failed(.malformed("Unknown backlight state")), .unreadable(.malformed("Unknown backlight state"))),
      (.displays([unknown]), .unknownActivity),
      (.legacy(integrated: []), .legacyIntegratedDisplays(count: 0)),
      (.legacy(integrated: [geometry, geometry]), .legacyIntegratedDisplays(count: 2)),
      (
        .displays([
          inactive,
          SimulatorDisplay(
            uniqueID: "cover", name: "cover", activity: .inactive, isPrimary: false, isIntegrated: true, bounds: cover.bounds, scale: 2,
            rotation: .upright),
        ]), .noActiveIntegratedDisplay
      ),
      (.displays([cover, display("inner")]), .ambiguousActiveDisplays(["cover", "inner"])),
    ]
    for (report, fallback) in cases {
      let resolved = try await DisplayCommandsDouble([.success(report)]).resolveDisplay()
      XCTAssertEqual(resolved, .fallback(fallback))
    }
  }

  func testFallbackIsAChangeFromAReportedDisplay() async throws {
    let displays = DisplayCommandsDouble([.success(.failed(.unsupported("displayinfo")))])
    do {
      try await displays.validate(.identified(display("lcd")))
      XCTFail("Expected a display change")
    } catch SimulatorDisplayError.changed {}
  }

  func testRequiredCapabilityIsCheckedOfTheGuest() async throws {
    let selected = DisplayCommandsDouble(.selected(display("inner")))
    selected.identities.remember(inventory)
    let oldGuest = InventoryTransport(inventory)
    do {
      _ = try await selected.accessibilityID(for: display("inner"), transport: oldGuest, requiring: .scopedInteractions)
      XCTFail("Expected the guest to lack scoped interactions")
    } catch SimulatorDisplayInteractionError.unsupportedCapability {}
    let oldGuestSends = await oldGuest.sends
    XCTAssertEqual(oldGuestSends, 1)

    let currentGuest = InventoryTransport(inventory, scopedInteractions: true)
    for _ in 0..<2 {
      let resolved = try await selected.accessibilityID(for: display("inner"), transport: currentGuest, requiring: .scopedInteractions)
      XCTAssertEqual(resolved, 3)
    }
    let currentGuestSends = await currentGuest.sends
    XCTAssertEqual(currentGuestSends, 1)
  }

  func testLookupDuringADisplayTransitionSettlesOnTheNextReport() async throws {
    let settled = Result<SimulatorDisplayReport, any Error>.success(.reporting(.selected(display("inner"))))
    let touchscreens = [SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: 29)]
    let accessibility = DisplayCommandsDouble([transition, settled])
    let hid = DisplayCommandsDouble([transition, settled], touchscreens: touchscreens)
    let context = DisplayCommandsDouble([transition, settled], touchscreens: touchscreens)
    let transport = InventoryTransport(inventory)
    let accessibilityID = await outcome { try await accessibility.accessibilityID(for: selected(accessibility), transport: transport) }
    let digitizerTarget = await outcome { try await hid.digitizerTarget(for: selected(hid)) }
    let contextTarget = await outcome { try await context.interactionContext(for: nil, transport: transport).digitizerTarget }
    XCTAssertEqual(try accessibilityID.get(), 3)
    XCTAssertEqual(try digitizerTarget.get(), 29)
    XCTAssertEqual(try contextTarget.get(), 29)
    XCTAssertEqual([accessibility.reads, hid.reads, context.reads], [3, 3, 3])
  }

  func testLookupFailsWhenADisplayTransitionDoesNotSettle() async throws {
    let displays = DisplayCommandsDouble([transition])
    let resolved = try await displays.resolveDisplay()
    XCTAssertEqual(resolved, .transitioning)
    XCTAssertGreaterThan(displays.reads, 1)
    let hid = DisplayCommandsDouble([transition], touchscreens: [SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: 29)])
    assertTransitioning(await outcome { try await hid.digitizerTarget(for: display("inner")) })
    assertTransitioning(await outcome { try await displays.interactionContext(for: nil, transport: InventoryTransport(inventory)) })
  }

  private func selected(_ displays: DisplayCommandsDouble) async throws -> SimulatorDisplay {
    guard case let .target(.selected(display)) = try await displays.resolveDisplay() else {
      throw SimulatorDisplayInteractionError.unsupportedCapability("a selected display")
    }
    return display
  }

  private let transition = Result<SimulatorDisplayReport, any Error>.success(.transitioning)

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

  func testDescribingNamesIdentifiedDisplaysAndNoLegacyOnes() {
    let geometry = display("lcd").geometry
    guard case let .read(displays) = SimulatorDisplayCommands.describedDisplays(in: .displays([display("cover"), display("inner")])) else {
      return XCTFail("identified displays are read")
    }
    XCTAssertEqual(displays.map(\.uniqueID), ["cover", "inner"])
    guard case let .read(legacy) = SimulatorDisplayCommands.describedDisplays(in: .legacy(integrated: [geometry])) else {
      return XCTFail("a legacy runtime is read")
    }
    XCTAssertEqual(legacy, [])
    guard case .failed = SimulatorDisplayCommands.describedDisplays(in: .transitioning) else { return XCTFail("a transition fails") }
    guard case .failed = SimulatorDisplayCommands.describedDisplays(in: .failed(.malformed("unreadable"))) else {
      return XCTFail("an unreadable report fails")
    }
  }

  func testADisplayIsDescribedInItsCurrentOrientation() {
    let display = SimulatorDisplay(
      uniqueID: "FA9C9507-0D45-4189-A7D6-A3335032D47B", name: "LCD-1", activity: .active, isPrimary: false, isIntegrated: true,
      bounds: CGRect(x: 0, y: 0, width: 2008, height: 2854), scale: 3, rotation: .clockwise)

    XCTAssertEqual(
      TargetDisplayDescription(display),
      TargetDisplayDescription(
        uniqueID: "FA9C9507-0D45-4189-A7D6-A3335032D47B", name: "LCD-1", isActive: true, isIntegrated: true, widthPixels: 2854,
        heightPixels: 2008, scale: 3))
  }

  func testAnInactiveExternalDisplayIsDescribedAsSuch() {
    let display = SimulatorDisplay(
      uniqueID: "F774281A-0000-0000-0000-000000000000", name: "TVOut", activity: .inactive, isPrimary: false, isIntegrated: false,
      bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1, rotation: .upright)

    let described = TargetDisplayDescription(display)

    XCTAssertFalse(described.isActive)
    XCTAssertFalse(described.isIntegrated)
    XCTAssertEqual(described.widthPixels, 1920)
    XCTAssertEqual(described.heightPixels, 1080)
  }

  func testADisplayWithoutAUsableSizeIsDescribedWithNone() {
    let display = SimulatorDisplay(
      uniqueID: "F774281A-0000-0000-0000-000000000000", name: "TVOut", activity: .inactive, isPrimary: false, isIntegrated: false,
      bounds: CGRect(x: 0, y: 0, width: CGFloat.nan, height: -1), scale: 1, rotation: .upright)

    let described = TargetDisplayDescription(display)

    XCTAssertEqual(described.widthPixels, 0)
    XCTAssertEqual(described.heightPixels, 0)
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import XCTest

final class SimulatorDisplayInteractionTests: XCTestCase {
  private func display(
    id: String = "inner", active: Bool = true, rotation: SimulatorDisplayRotation = .upright, scale: Double = 2
  ) -> SimulatorDisplay {
    SimulatorDisplay(
      uniqueID: id, name: id, activity: active ? .active : .inactive, isPrimary: false, isIntegrated: true,
      bounds: CGRect(x: 50, y: 60, width: 1200, height: 800), scale: scale, rotation: rotation)
  }

  private let accessibility = [SimulatorAccessibilityDisplay(uniqueID: "inner", displayID: 82)]

  private func context(_ display: SimulatorDisplay) throws -> SimulatorDisplayInteractionContext {
    try SimulatorDisplayInteractionContext.join(
      display: display,
      touchscreens: [SimulatorTouchscreen(displayUniqueID: display.uniqueID, digitizerTarget: 29)],
      accessibility: [SimulatorAccessibilityDisplay(uniqueID: display.uniqueID, displayID: 82)])
  }

  func testHIDBindingNeedsOnlyTheMatchingTouchscreenIdentity() async throws {
    let selected = display()
    let displays = DisplayCommandsDouble(
      .selected(selected),
      touchscreens: [
        SimulatorTouchscreen(displayUniqueID: "cover", digitizerTarget: 29),
        SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: 82),
      ])
    let target = try await displays.digitizerTarget(for: selected)
    XCTAssertEqual(target, 82)
    let cached = try await displays.digitizerTarget(for: selected)
    XCTAssertEqual(cached, target)
    XCTAssertEqual(displays.touchscreenReads, 1)

    let binding = SimulatorHIDDisplay.selected(selected, target: target)
    let identified = SimulatorHIDDisplay.sole(.identified(selected))
    let legacy = SimulatorHIDDisplay.sole(.legacy(selected.geometry))
    XCTAssertEqual(binding.digitizerTarget, 82)
    XCTAssertEqual(binding.geometry, selected.geometry)
    XCTAssertEqual(identified.digitizerTarget, 0)
    XCTAssertEqual(legacy.digitizerTarget, 0)
    XCTAssertFalse(binding.hasSameConfiguration(as: identified))
    XCTAssertFalse(identified.hasSameConfiguration(as: legacy))
  }

  func testHIDBindingRejectsAmbiguousAndMissingTargets() async {
    let selected = display()
    let target = SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: 82)
    for targets in [[], [target, target], [SimulatorTouchscreen(displayUniqueID: "cover", digitizerTarget: 82)]] {
      do {
        _ = try await DisplayCommandsDouble(.selected(selected), touchscreens: targets).digitizerTarget(for: selected)
        XCTFail("Expected a unique target requirement")
      } catch {
        guard case SimulatorDisplayInteractionError.unsupportedCapability = error else {
          return XCTFail("Unexpected mapping error: \(error)")
        }
      }
    }
  }

  func testHIDBindingIsNotCachedWhenTheDisplayChangesDuringLookup() async {
    let displays = DisplayCommandsDouble(
      .selected(display(id: "cover")),
      touchscreens: [SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: 82)])
    do {
      _ = try await displays.digitizerTarget(for: display())
      XCTFail("Expected a display change")
    } catch {
      guard case SimulatorDisplayError.changed = error else { return XCTFail("Unexpected error: \(error)") }
    }
    XCTAssertNil(displays.identities.digitizerTarget(for: "inner"))
  }

  func testHIDGeometryRotatesPointsAndEdgesTogether() throws {
    let cases: [(SimulatorDisplayRotation, CGPoint, SimulatorHIDEdge)] = [
      (.upright, CGPoint(x: 0.2, y: 0.3), .top),
      (.clockwise, CGPoint(x: 0.3, y: 0.8), .left),
      (.upsideDown, CGPoint(x: 0.8, y: 0.7), .bottom),
      (.counterclockwise, CGPoint(x: 0.7, y: 0.2), .right),
    ]
    for (rotation, expected, edge) in cases {
      let selected = display(rotation: rotation, scale: 3)
      for binding in [SimulatorHIDDisplay.selected(selected, target: 82), .sole(.legacy(selected.geometry))] {
        let size = binding.geometry.pointSize
        let point = try binding.normalizedPoint(CGPoint(x: size.width * 0.2, y: size.height * 0.3))
        XCTAssertEqual(point.x, expected.x, accuracy: 0.000001)
        XCTAssertEqual(point.y, expected.y, accuracy: 0.000001)
        XCTAssertEqual(binding.unrotatedEdge(.top), edge)
        XCTAssertEqual(binding.unrotatedEdge(.none), .none)
        XCTAssertThrowsError(try binding.normalizedPoint(CGPoint(x: size.width + 1, y: 0)))
      }
    }
    let first = SimulatorHIDDisplay.selected(display(), target: 82)
    XCTAssertFalse(first.hasSameConfiguration(as: .selected(display(), target: 29)))
    XCTAssertFalse(first.hasSameConfiguration(as: .selected(display(rotation: .clockwise), target: 82)))
  }

  func testJoinUsesUUIDAcrossIndependentNumericNamespaces() throws {
    let result = try SimulatorDisplayInteractionContext.join(
      display: display(),
      touchscreens: [
        SimulatorTouchscreen(displayUniqueID: "cover", digitizerTarget: 82),
        SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: 29),
      ],
      accessibility: [
        SimulatorAccessibilityDisplay(uniqueID: "inner", displayID: 82),
        SimulatorAccessibilityDisplay(uniqueID: "cover", displayID: 29),
      ])
    XCTAssertEqual(result.display.uniqueID, "inner")
    XCTAssertEqual(result.accessibilityDisplayID, 82)
    XCTAssertEqual(result.digitizerTarget, 29)
  }

  func testMissingAndDuplicateMappingsFail() throws {
    let touchscreen = SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: 29)
    let axDisplay = SimulatorAccessibilityDisplay(uniqueID: "inner", displayID: 82)
    for touchscreens in [[], [touchscreen, touchscreen]] {
      XCTAssertThrowsError(try SimulatorDisplayInteractionContext.join(display: display(), touchscreens: touchscreens, accessibility: [axDisplay]))
    }
    for accessibility in [[], [axDisplay, axDisplay]] {
      XCTAssertThrowsError(try SimulatorDisplayInteractionContext.join(display: display(), touchscreens: [touchscreen], accessibility: accessibility))
    }
  }

  func testCoordinatesUseDisplayRelativePointsAndInverseInterfaceRotation() throws {
    let cases: [(SimulatorDisplayRotation, CGSize, CGPoint)] = [
      (.upright, CGSize(width: 600, height: 400), CGPoint(x: 0.2, y: 0.3)),
      (.clockwise, CGSize(width: 400, height: 600), CGPoint(x: 0.3, y: 0.8)),
      (.upsideDown, CGSize(width: 600, height: 400), CGPoint(x: 0.8, y: 0.7)),
      (.counterclockwise, CGSize(width: 400, height: 600), CGPoint(x: 0.7, y: 0.2)),
    ]
    for (rotation, size, expected) in cases {
      let context = try context(display(rotation: rotation))
      XCTAssertEqual(context.pointSize, size)
      let actual = try context.digitizerPoint(from: CGPoint(x: size.width * 0.2, y: size.height * 0.3))
      XCTAssertEqual(actual.x, expected.x, accuracy: 0.000001)
      XCTAssertEqual(actual.y, expected.y, accuracy: 0.000001)
    }
    let context = try context(display(scale: 3))
    XCTAssertEqual(context.pointSize, CGSize(width: 400, height: 800.0 / 3))
    for point in [CGPoint(x: -1, y: 0), CGPoint(x: 401, y: 0), CGPoint(x: 0, y: 300), CGPoint(x: Double.nan, y: 0), CGPoint(x: 0, y: Double.infinity)] {
      XCTAssertThrowsError(try context.digitizerPoint(from: point))
    }
  }

  func testInventoryRejectsInvalidIDsAndPreservesUnsupportedFailure() throws {
    let valid = Data(#"{"ok":true,"displays":[{"uniqueID":"inner","displayID":82}]}"#.utf8)
    XCTAssertEqual(try AXBridgeDisplayInventory.decode(valid), [SimulatorAccessibilityDisplay(uniqueID: "inner", displayID: 82)])
    for id in ["0", "-1", "4294967296", "true", "1.5", #""82""#] {
      let data = Data("{\"ok\":true,\"displays\":[{\"uniqueID\":\"inner\",\"displayID\":\(id)}]}".utf8)
      XCTAssertThrowsError(try AXBridgeDisplayInventory.decode(data))
    }
    for json in [
      #"{"ok":true}"#,
      #"{"ok":true,"displays":[{"uniqueID":"","displayID":82}]}"#,
      #"{"ok":true,"displays":[{"uniqueID":"a","displayID":82},{"uniqueID":"b","displayID":82}]}"#,
      #"{"ok":true,"displays":[{"uniqueID":"a","displayID":82},{"uniqueID":"a","displayID":29}]}"#,
    ] {
      XCTAssertThrowsError(try AXBridgeDisplayInventory.decode(Data(json.utf8)))
    }
    XCTAssertThrowsError(try AXBridgeDisplayInventory.decode(Data(#"{"ok":false,"error_kind":"capability_unavailable"}"#.utf8))) {
      guard case SimulatorDisplayInteractionError.unsupportedCapability = $0 else { return XCTFail("\($0)") }
    }
    XCTAssertThrowsError(try AXBridgeDisplayInventory.decode(Data(#"{"ok":false,"error_kind":"reader_unavailable","error":"failed"}"#.utf8))) {
      guard case AXBridgeError.readerUnavailable = $0 else { return XCTFail("\($0)") }
    }
    XCTAssertEqual(try AXBridgeRequest.displays.command, .accessibility(["verb": .string("displays")]))
    XCTAssertEqual(AXBridgeRequest.displays.payload as NSDictionary, ["verb": "displays"])
    XCTAssertTrue(AXBridgeRequest.displays.mayRetry)
  }

  func testScopedInteractionsRequireGuestAdvertisement() throws {
    let oldGuest = Data(#"{"ok":true,"displays":[{"uniqueID":"inner","displayID":82}]}"#.utf8)
    XCTAssertEqual(try AXBridgeDisplayInventory.decode(oldGuest).count, 1)
    XCTAssertThrowsError(try AXBridgeDisplayInventory.decode(oldGuest, requiring: .scopedInteractions)) {
      guard case SimulatorDisplayInteractionError.unsupportedCapability = $0 else { return XCTFail("\($0)") }
    }
    let currentGuest = Data(#"{"ok":true,"displayScopedInteractions":true,"displays":[{"uniqueID":"inner","displayID":82}]}"#.utf8)
    XCTAssertEqual(try AXBridgeDisplayInventory.decode(currentGuest, requiring: .scopedInteractions).count, 1)
    XCTAssertThrowsError(try AXBridgeDisplayInventory.decode(currentGuest, requiring: .scopedTrees))
    let scopedGuest = Data(#"{"ok":true,"displayScopedTrees":true,"displays":[{"uniqueID":"inner","displayID":82}]}"#.utf8)
    XCTAssertEqual(try AXBridgeDisplayInventory.decode(scopedGuest, requiring: .scopedTrees).count, 1)
  }

  func testResolutionChecksActivityAgainAfterAcquiringMappings() async throws {
    let displays = DisplayCommandsDouble(
      .selected(display()), .selected(display(id: "cover")),
      touchscreens: [SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: 29)])
    do {
      _ = try await displays.interactionContext(for: nil, transport: InventoryTransport(accessibility))
      XCTFail("Expected a transition error")
    } catch { guard case SimulatorDisplayError.changed = error else { return XCTFail("\(error)") } }
  }

  func testExplicitInactiveSelectionDoesNotQueryRoutingProviders() async throws {
    let displays = DisplayCommandsDouble(.selected(display()))
    let transport = InventoryTransport(accessibility)
    do {
      _ = try await displays.interactionContext(for: "cover", transport: transport)
      XCTFail("Expected inactive selection failure")
    } catch { guard case SimulatorDisplayInteractionError.inactiveDisplay("cover") = error else { return XCTFail("\(error)") } }
    let sends = await transport.sends
    XCTAssertEqual(displays.touchscreenReads, 0)
    XCTAssertEqual(sends, 0)
  }

  func testSoleDisplayContextCarriesBothIdentities() async throws {
    let displays = DisplayCommandsDouble(
      .sole(.identified(display())), touchscreens: [SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: 29)])
    let resolved = try await displays.interactionContext(for: nil, transport: InventoryTransport(accessibility))
    XCTAssertEqual(resolved, try context(display()))
    let legacy = DisplayCommandsDouble(.sole(.legacy(display().geometry)))
    do {
      _ = try await legacy.interactionContext(for: nil, transport: InventoryTransport(accessibility))
      XCTFail("Expected missing display identities")
    } catch { guard case SimulatorDisplayInteractionError.unsupportedCapability = error else { return XCTFail("\(error)") } }
  }

  func testValidationRejectsGeometryOrRoutingChanges() async throws {
    let saved = try context(display())
    let changedDisplays = [display(rotation: .clockwise), display(scale: 3), display()]
    for (index, updated) in changedDisplays.enumerated() {
      let displays = DisplayCommandsDouble(
        .selected(updated),
        touchscreens: [SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: index == 2 ? 30 : 29)])
      do {
        try await displays.validate(saved, transport: InventoryTransport(accessibility))
        XCTFail("Expected stale context failure")
      } catch { guard case SimulatorDisplayError.changed = error else { return XCTFail("\(error)") } }
    }
    let displays = DisplayCommandsDouble(
      .selected(display()), touchscreens: [SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: 29)])
    let resolved = try await displays.interactionContext(for: "inner", transport: InventoryTransport(accessibility))
    XCTAssertEqual(resolved, saved)
    try await displays.validate(saved, transport: InventoryTransport(accessibility))
  }
}

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
      let geometry = display(rotation: rotation, scale: 3).geometry
      let size = geometry.pointSize
      let point = try geometry.normalizedPoint(CGPoint(x: size.width * 0.2, y: size.height * 0.3))
      XCTAssertEqual(point.x, expected.x, accuracy: 0.000001)
      XCTAssertEqual(point.y, expected.y, accuracy: 0.000001)
      XCTAssertEqual(geometry.unrotatedEdge(.top), edge)
      XCTAssertEqual(geometry.unrotatedEdge(.none), .none)
      XCTAssertThrowsError(try geometry.normalizedPoint(CGPoint(x: size.width + 1, y: 0)))
    }
    let first = SimulatorHIDDisplay.selected(display(), target: 82)
    XCTAssertFalse(first.hasSameConfiguration(as: .selected(display(), target: 29)))
    XCTAssertFalse(first.hasSameConfiguration(as: .selected(display(rotation: .clockwise), target: 82)))
  }

  func testInvalidPointDescriptionsNameTheProblem() {
    XCTAssertEqual(
      SimulatorDisplayInteractionError.invalidPoint(CGPoint(x: 401, y: 0), bounds: CGSize(width: 400, height: 300)).localizedDescription,
      "Touch point (401.0, 0.0) is outside the display's point bounds (400.0 x 300.0)")
    XCTAssertEqual(
      SimulatorDisplayInteractionError.invalidPoint(CGPoint(x: Double.nan, y: 0), bounds: CGSize(width: 400, height: 300)).localizedDescription,
      "Touch point (nan, 0.0) is not a real position (x is NaN) within the display's point bounds (400.0 x 300.0)")
    XCTAssertEqual(
      SimulatorDisplayInteractionError.invalidPoint(CGPoint(x: 0, y: -Double.infinity), bounds: CGSize(width: 400, height: 300)).localizedDescription,
      "Touch point (0.0, -inf) is not a real position (y is infinite) within the display's point bounds (400.0 x 300.0)")
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
}

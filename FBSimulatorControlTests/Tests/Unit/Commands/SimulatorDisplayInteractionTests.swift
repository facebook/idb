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
      uniqueID: id, name: id, isActive: active, isPrimary: false, isIntegrated: true,
      bounds: CGRect(x: 50, y: 60, width: 1200, height: 800), scale: scale, rotation: rotation)
  }

  private func context(_ display: SimulatorDisplay) throws -> SimulatorDisplayInteractionContext {
    try SimulatorDisplayInteractionResolver.join(
      display: display,
      touchscreens: [SimulatorTouchscreen(displayUniqueID: display.uniqueID, digitizerTarget: 29)],
      accessibility: [SimulatorAccessibilityDisplay(uniqueID: display.uniqueID, displayID: 82)])
  }

  func testJoinUsesUUIDAcrossIndependentNumericNamespaces() throws {
    let result = try SimulatorDisplayInteractionResolver.join(
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
      XCTAssertThrowsError(try SimulatorDisplayInteractionResolver.join(display: display(), touchscreens: touchscreens, accessibility: [axDisplay]))
    }
    for accessibility in [[], [axDisplay, axDisplay]] {
      XCTAssertThrowsError(try SimulatorDisplayInteractionResolver.join(display: display(), touchscreens: [touchscreen], accessibility: accessibility))
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

  func testResolutionChecksActivityAgainAfterAcquiringMappings() async throws {
    let original = display()
    let changed = display(id: "cover")
    let reads = DisplayReadSequence([[original], [changed]])
    let resolver = SimulatorDisplayInteractionResolver(
      readDisplays: { await reads.next() },
      readTouchscreens: { [SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: 29)] },
      readAccessibility: { [SimulatorAccessibilityDisplay(uniqueID: "inner", displayID: 82)] })
    do {
      _ = try await resolver.resolve()
      XCTFail("Expected a transition error")
    } catch { guard case SimulatorDisplayError.changed = error else { return XCTFail("\(error)") } }
  }

  func testExplicitInactiveSelectionDoesNotQueryRoutingProviders() async throws {
    let original = display()
    let resolver = SimulatorDisplayInteractionResolver(
      readDisplays: { [original] },
      readTouchscreens: {
        XCTFail("Inactive display must fail before routing discovery")
        return []
      },
      readAccessibility: {
        XCTFail("Inactive display must fail before AX discovery")
        return []
      })
    do {
      _ = try await resolver.resolve(displayUniqueID: "cover")
      XCTFail("Expected inactive selection failure")
    } catch { guard case SimulatorDisplayInteractionError.inactiveDisplay("cover") = error else { return XCTFail("\(error)") } }
  }

  func testValidationRejectsGeometryOrRoutingChanges() async throws {
    let saved = try context(display())
    let changedDisplays = [display(rotation: .clockwise), display(scale: 3), display()]
    for (index, updated) in changedDisplays.enumerated() {
      let resolver = SimulatorDisplayInteractionResolver(
        readDisplays: { [updated] },
        readTouchscreens: { [SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: index == 2 ? 30 : 29)] },
        readAccessibility: { [SimulatorAccessibilityDisplay(uniqueID: "inner", displayID: 82)] })
      do {
        try await resolver.validate(saved)
        XCTFail("Expected stale context failure")
      } catch { guard case SimulatorDisplayError.changed = error else { return XCTFail("\(error)") } }
    }
    let unchanged = display()
    let resolver = SimulatorDisplayInteractionResolver(
      readDisplays: { [unchanged] },
      readTouchscreens: { [SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: 29)] },
      readAccessibility: { [SimulatorAccessibilityDisplay(uniqueID: "inner", displayID: 82)] })
    let resolved = try await resolver.resolve(displayUniqueID: "inner")
    XCTAssertEqual(resolved, saved)
    try await resolver.validate(saved)
  }
}

private actor DisplayReadSequence {
  var values: [[SimulatorDisplay]]
  init(_ values: [[SimulatorDisplay]]) { self.values = values }
  func next() -> [SimulatorDisplay] { values.removeFirst() }
}

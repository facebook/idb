/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
@testable import FBSimulatorControl
import Foundation
import XCTest

final class FBRemoteAutomationPlatformElementTests: XCTestCase {

  func testMapsCoreStringAttributes() {
    let element = FBRemoteAutomationPlatformElement(
      attributes: [
        FBAXWire.Node.label.rawValue: "General",
        FBAXWire.Node.value.rawValue: "On",
        FBAXWire.Node.identifier.rawValue: "com.apple.settings.general",
        FBAXWire.Node.automationType.rawValue: "Button",
      ],
      children: [],
      pid: 42
    )

    XCTAssertEqual(element.axLabel(), "General")
    XCTAssertEqual(element.axValue() as? String, "On")
    XCTAssertEqual(element.axIdentifier(), "com.apple.settings.general")
    XCTAssertEqual(element.axRole(), "Button")
    XCTAssertEqual(element.axTranslationPid, 42)
  }

  func testParsesFrameFromDictionaryRepresentation() {
    let expected = CGRect(x: 16, y: 380, width: 370, height: 52)
    let element = FBRemoteAutomationPlatformElement(
      attributes: [
        FBAXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(expected) as NSDictionary
      ],
      children: [],
      pid: 0
    )

    let frame = element.axFrame()
    XCTAssertEqual(frame.origin.x, expected.origin.x, accuracy: 0.001)
    XCTAssertEqual(frame.origin.y, expected.origin.y, accuracy: 0.001)
    XCTAssertEqual(frame.size.width, expected.size.width, accuracy: 0.001)
    XCTAssertEqual(frame.size.height, expected.size.height, accuracy: 0.001)
  }

  func testParsesFrameFromNSValueFallback() {
    let expected = NSRect(x: 0, y: 0, width: 402, height: 874)
    let element = FBRemoteAutomationPlatformElement(
      attributes: [FBAXWire.Node.frame.rawValue: NSValue(rect: expected)],
      children: [],
      pid: 0
    )
    XCTAssertEqual(element.axFrame(), expected)
  }

  func testFrameWithNullMemberKeepsTheReadableEdgesWithoutCrashing() {
    // An off-screen or still-settling element reports a non-finite frame coordinate; because JSON has
    // no infinity/NaN, the guest emits that member as null, which arrives host-side as NSNull.
    // `CGRectMakeWithDictionaryRepresentation` sends a number selector to every member, so a null one
    // would raise `-[NSNull _getValue:forType:]` and terminate the read. It must never see one.
    //
    // Restoring the null to the non-finite value it stands for satisfies that and keeps the edges the
    // guest did send. Degrading the whole rectangle to `.zero` also avoided the crash, but reported an
    // off-screen element as sitting at the origin with no size — a real position rather than an absent
    // one. `FBAccessibilityFrame` normalizes the non-finite edge to null downstream.
    let frameDict = NSMutableDictionary(
      dictionary: CGRectCreateDictionaryRepresentation(CGRect(x: 0, y: 0, width: 10, height: 20)) as NSDictionary
    )
    frameDict["X"] = NSNull()
    let element = FBRemoteAutomationPlatformElement(
      attributes: [FBAXWire.Node.frame.rawValue: frameDict],
      children: [],
      pid: 0
    )

    let frame = element.axFrame()
    XCTAssertFalse(frame.origin.x.isFinite, "the null member is the coordinate the guest could not send")
    XCTAssertEqual(frame.origin.y, 0)
    XCTAssertEqual(frame.size.width, 10)
    XCTAssertEqual(frame.size.height, 20)
  }

  func testRoleMapsElementTypeNumberToReadableName() {
    let element = FBRemoteAutomationPlatformElement(
      attributes: [FBAXWire.Node.elementType.rawValue: NSNumber(value: 9)],
      children: [],
      pid: 0
    )
    XCTAssertEqual(element.axRole(), "Button")
  }

  func testRolePrefersAutomationTypeNameOverElementType() {
    let element = FBRemoteAutomationPlatformElement(
      attributes: [
        FBAXWire.Node.automationType.rawValue: NSNumber(value: 48),
        FBAXWire.Node.elementType.rawValue: NSNumber(value: 9),
      ],
      children: [],
      pid: 0
    )
    XCTAssertEqual(element.axRole(), "StaticText")
  }

  func testRoleFallsBackToRawStringForUnknownElementType() {
    let element = FBRemoteAutomationPlatformElement(
      attributes: [FBAXWire.Node.elementType.rawValue: NSNumber(value: 9999)],
      children: [],
      pid: 0
    )
    XCTAssertEqual(element.axRole(), "9999")
  }

  func testChildrenAreExposed() {
    let child = FBRemoteAutomationPlatformElement(
      attributes: [FBAXWire.Node.label.rawValue: "About"],
      children: [],
      pid: 7
    )
    let root = FBRemoteAutomationPlatformElement(
      attributes: [FBAXWire.Node.label.rawValue: "General"],
      children: [child],
      pid: 7
    )

    let children = root.axChildren()
    XCTAssertEqual(children.count, 1)
    XCTAssertEqual(children.first?.axLabel(), "About")
  }

  func testAbsentAttributesUseSafeDefaults() {
    let element = FBRemoteAutomationPlatformElement(attributes: [:], children: [], pid: 0)

    XCTAssertNil(element.axLabel())
    XCTAssertNil(element.axValue())
    XCTAssertNil(element.axRole())
    XCTAssertNil(element.axTitle())
    XCTAssertNil(element.axTraits())
    XCTAssertEqual(element.axFrame(), .zero)
    XCTAssertTrue(element.axIsEnabled())
    XCTAssertFalse(element.axIsHidden())
    XCTAssertTrue(element.axChildren().isEmpty)
    XCTAssertTrue(element.axActionNames().isEmpty)
  }
}

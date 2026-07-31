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
        FBRemoteAutomationAXAttribute.label: "General",
        FBRemoteAutomationAXAttribute.value: "On",
        FBRemoteAutomationAXAttribute.identifier: "com.apple.settings.general",
        FBRemoteAutomationAXAttribute.automationType: "Button",
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
        FBRemoteAutomationAXAttribute.frame: CGRectCreateDictionaryRepresentation(expected) as NSDictionary
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
      attributes: [FBRemoteAutomationAXAttribute.frame: NSValue(rect: expected)],
      children: [],
      pid: 0
    )
    XCTAssertEqual(element.axFrame(), expected)
  }

  func testFrameWithNullMemberDegradesToZeroWithoutCrashing() {
    // An off-screen or still-settling element reports a non-finite frame coordinate; because JSON has
    // no infinity/NaN, the guest emits that member as null, which arrives host-side as NSNull.
    // `CGRectMakeWithDictionaryRepresentation` sends a number selector to every member, so a null one
    // would raise `-[NSNull _getValue:forType:]` and terminate the read. The frame must degrade to
    // `.zero` instead of crashing.
    let frameDict = NSMutableDictionary(
      dictionary: CGRectCreateDictionaryRepresentation(CGRect(x: 0, y: 0, width: 10, height: 20)) as NSDictionary
    )
    frameDict["X"] = NSNull()
    let element = FBRemoteAutomationPlatformElement(
      attributes: [FBRemoteAutomationAXAttribute.frame: frameDict],
      children: [],
      pid: 0
    )

    XCTAssertEqual(element.axFrame(), .zero)
  }

  func testRoleMapsElementTypeNumberToReadableName() {
    let element = FBRemoteAutomationPlatformElement(
      attributes: [FBRemoteAutomationAXAttribute.elementType: NSNumber(value: 9)],
      children: [],
      pid: 0
    )
    XCTAssertEqual(element.axRole(), "Button")
  }

  func testRolePrefersAutomationTypeNameOverElementType() {
    let element = FBRemoteAutomationPlatformElement(
      attributes: [
        FBRemoteAutomationAXAttribute.automationType: NSNumber(value: 48),
        FBRemoteAutomationAXAttribute.elementType: NSNumber(value: 9),
      ],
      children: [],
      pid: 0
    )
    XCTAssertEqual(element.axRole(), "StaticText")
  }

  func testRoleFallsBackToRawStringForUnknownElementType() {
    let element = FBRemoteAutomationPlatformElement(
      attributes: [FBRemoteAutomationAXAttribute.elementType: NSNumber(value: 9999)],
      children: [],
      pid: 0
    )
    XCTAssertEqual(element.axRole(), "9999")
  }

  func testChildrenAreExposed() {
    let child = FBRemoteAutomationPlatformElement(
      attributes: [FBRemoteAutomationAXAttribute.label: "About"],
      children: [],
      pid: 7
    )
    let root = FBRemoteAutomationPlatformElement(
      attributes: [FBRemoteAutomationAXAttribute.label: "General"],
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
    XCTAssertFalse(element.axPerformPress())
  }

  func testFetchListCoversTheReadAttributes() {
    let list = FBRemoteAutomationAXAttribute.fetchList
    XCTAssertTrue(list.contains(FBRemoteAutomationAXAttribute.label))
    XCTAssertTrue(list.contains(FBRemoteAutomationAXAttribute.frame))
    XCTAssertTrue(list.contains(FBRemoteAutomationAXAttribute.children))
    XCTAssertTrue(list.contains(FBRemoteAutomationAXAttribute.identifier))
  }
}

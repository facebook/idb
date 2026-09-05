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

final class FBAXBridgePlatformElementTests: XCTestCase {

  func testMapsCoreStringAttributes() {
    let element = FBAXBridgePlatformElement(
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
    let element = FBAXBridgePlatformElement(
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
    let element = FBAXBridgePlatformElement(
      attributes: [FBAXWire.Node.frame.rawValue: NSValue(rect: expected)],
      children: [],
      pid: 0
    )
    XCTAssertEqual(element.axFrame(), expected)
  }

  func testFrameWithNullMemberKeepsTheReadableEdgesWithoutCrashing() {
    // The guest sends a non-finite frame member as JSON null (arriving as NSNull). `CGRectMakeWithDictionaryRepresentation`
    // would raise `-[NSNull _getValue:forType:]` on it, so the null is restored to a non-finite value and the other
    // edges are kept rather than collapsing the rect to `.zero` (a real position for an off-screen element).
    let frameDict = NSMutableDictionary(
      dictionary: CGRectCreateDictionaryRepresentation(CGRect(x: 0, y: 0, width: 10, height: 20)) as NSDictionary
    )
    frameDict["X"] = NSNull()
    let element = FBAXBridgePlatformElement(
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
    let element = FBAXBridgePlatformElement(
      attributes: [FBAXWire.Node.elementType.rawValue: NSNumber(value: 9)],
      children: [],
      pid: 0
    )
    XCTAssertEqual(element.axRole(), "Button")
  }

  func testRolePrefersAutomationTypeNameOverElementType() {
    let element = FBAXBridgePlatformElement(
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
    let element = FBAXBridgePlatformElement(
      attributes: [FBAXWire.Node.elementType.rawValue: NSNumber(value: 9999)],
      children: [],
      pid: 0
    )
    XCTAssertEqual(element.axRole(), "9999")
  }

  // `Any` is `XCUIElementType` 0 — a successful lookup, not a miss — so it must not short-circuit past the
  // concrete class name the read already carried.
  func testRoleReportsTheConcreteElementTypeRatherThanAny() {
    let element = FBAXBridgePlatformElement(
      attributes: [
        FBAXWire.Node.automationType.rawValue: NSNumber(value: 0),
        FBAXWire.Node.elementType.rawValue: "AppRefreshControl",
      ],
      children: [],
      pid: 0
    )

    XCTAssertEqual(element.axRole(), "AppRefreshControl")
  }

  // An automation type that resolves to no name (a stringified number) must also lose to the concrete class name.
  func testRoleReportsTheConcreteElementTypeRatherThanAStringifiedAutomationType() {
    let element = FBAXBridgePlatformElement(
      attributes: [
        FBAXWire.Node.automationType.rawValue: NSNumber(value: 9999),
        FBAXWire.Node.elementType.rawValue: "AppRefreshControl",
      ],
      children: [],
      pid: 0
    )

    XCTAssertEqual(element.axRole(), "AppRefreshControl")
  }

  // With nothing better than `Any`, report `Any` — not the literal string "0".
  func testRoleStillReportsAnyWhenThereIsNoConcreteElementType() {
    let element = FBAXBridgePlatformElement(
      attributes: [FBAXWire.Node.automationType.rawValue: NSNumber(value: 0)],
      children: [],
      pid: 0
    )

    XCTAssertEqual(element.axRole(), "Any")
  }

  // The mapping is partial by construction; a bare role number must not reach a caller as an `XCUIElementType` name.
  func testUnidentifiedTranslatorRoleReportsNoType() {
    let element = FBAXBridgePlatformElement(
      attributes: [FBAXWire.Node.translatorRole.rawValue: NSNumber(value: 99)],
      children: [],
      pid: 0
    )
    XCTAssertNil(element.axRole(), "an unidentified role must not surface as a number")
  }

  // A toggle is `CheckBox` and a search field is `TextField`: `Switch` and `SearchField` live in the subrole.
  func testTranslatorRolesAreMappedAcrossTheDecodedTable() {
    let cases: [(Int, String)] = [
      (1, "Application"), (2, "Button"), (3, "CheckBox"), (5, "Group"),
      (6, "Heading"), (14, "StaticText"), (15, "TextField"), (21, "Grid"),
    ]
    for (raw, expected) in cases {
      let element = FBAXBridgePlatformElement(
        attributes: [FBAXWire.Node.translatorRole.rawValue: NSNumber(value: raw)],
        children: [],
        pid: 0
      )
      XCTAssertEqual(element.axRole(), expected, "translator role \(raw)")
    }
  }

  // Both refined names are in the interactable role set; neither bare role is.
  func testASubroleRefinesTheRoleItAccompanies() {
    let toggle = FBAXBridgePlatformElement(
      attributes: [
        FBAXWire.Node.translatorRole.rawValue: NSNumber(value: 3),
        FBAXWire.Node.translatorSubrole.rawValue: NSNumber(value: 3),
      ],
      children: [],
      pid: 0
    )
    XCTAssertEqual(toggle.axRole(), "Switch", "a toggle is a check box with a switch subrole")

    let search = FBAXBridgePlatformElement(
      attributes: [
        FBAXWire.Node.translatorRole.rawValue: NSNumber(value: 15),
        FBAXWire.Node.translatorSubrole.rawValue: NSNumber(value: 1),
      ],
      children: [],
      pid: 0
    )
    XCTAssertEqual(search.axRole(), "SearchField", "a search field is a text field with a search subrole")
  }

  func testAnUnidentifiedSubroleFallsBackToTheRole() {
    let element = FBAXBridgePlatformElement(
      attributes: [
        FBAXWire.Node.translatorRole.rawValue: NSNumber(value: 2),
        FBAXWire.Node.translatorSubrole.rawValue: NSNumber(value: 99),
      ],
      children: [],
      pid: 0
    )
    XCTAssertEqual(element.axRole(), "Button")
  }

  func testXCUIElementTypeOutranksTheTranslatorRole() {
    let element = FBAXBridgePlatformElement(
      attributes: [
        FBAXWire.Node.automationType.rawValue: NSNumber(value: 48),
        FBAXWire.Node.translatorRole.rawValue: NSNumber(value: 2),
      ],
      children: [],
      pid: 0
    )
    XCTAssertEqual(element.axRole(), "StaticText")
  }

  // Only a translator-vocabulary read carries `enabled` (under the reader's own key); every other read must stay
  // unknown rather than report a fabricated `false`.
  func testEnabledIsReadFromATranslatorNodeAndStaysUnknownOnEveryOtherRead() {
    let translator = FBAXBridgePlatformElement(
      attributes: [FBAXWire.Node.isEnabled.rawValue: false],
      children: [],
      pid: 7
    )
    XCTAssertEqual(translator.axIsEnabled(), false, "the translator's enabled answer must be reported")

    let xctest = FBAXBridgePlatformElement(
      attributes: [FBAXWire.Node.label.rawValue: "General"],
      children: [],
      pid: 7
    )
    XCTAssertNil(xctest.axIsEnabled(), "a read carrying no enabled answer must stay unknown")
  }

  func testAbsentAttributesUseSafeDefaults() {
    let element = FBAXBridgePlatformElement(attributes: [:], children: [], pid: 0)

    XCTAssertNil(element.axLabel())
    XCTAssertNil(element.axValue())
    XCTAssertNil(element.axRole())
    XCTAssertNil(element.axTitle())
    XCTAssertNil(element.axTraits())
    XCTAssertEqual(element.axFrame(), .zero)
    XCTAssertNil(element.axIsEnabled())
    XCTAssertFalse(element.axIsHidden())
    XCTAssertTrue(element.axChildren().isEmpty)
    XCTAssertTrue(element.axActionNames().isEmpty)
  }
}

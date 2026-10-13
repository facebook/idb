/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
@testable import FBSimulatorAX
@testable import FBSimulatorControl
import Foundation
import XCTest

final class AXBridgeSnapshotDecoderTests: XCTestCase {

  func testMapsCoreStringAttributes() {
    let element = AXBridgeSnapshotDecoder.snapshot(
      fromNode: [
        AXWire.Node.label.rawValue: "General",
        AXWire.Node.value.rawValue: "On",
        AXWire.Node.identifier.rawValue: "com.apple.settings.general",
        AXWire.Node.automationType.rawValue: "Button",
      ], pid: 42)

    XCTAssertEqual(element.label, "General")
    XCTAssertEqual(element.stringValue, "On")
    XCTAssertEqual(element.identifier, "com.apple.settings.general")
    XCTAssertEqual(element.role, "Button")
    XCTAssertEqual(element.pid, 42)
  }

  func testParsesFrameFromDictionaryRepresentation() {
    let expected = CGRect(x: 16, y: 380, width: 370, height: 52)
    let element = AXBridgeSnapshotDecoder.snapshot(
      fromNode: [
        AXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(expected) as NSDictionary
      ], pid: 0)

    let frame = element.frame
    XCTAssertEqual(frame.origin.x, expected.origin.x, accuracy: 0.001)
    XCTAssertEqual(frame.origin.y, expected.origin.y, accuracy: 0.001)
    XCTAssertEqual(frame.size.width, expected.size.width, accuracy: 0.001)
    XCTAssertEqual(frame.size.height, expected.size.height, accuracy: 0.001)
  }

  func testParsesFrameFromNSValueFallback() {
    let expected = NSRect(x: 0, y: 0, width: 402, height: 874)
    let element = AXBridgeSnapshotDecoder.snapshot(fromNode: [AXWire.Node.frame.rawValue: NSValue(rect: expected)], pid: 0)
    XCTAssertEqual(element.frame, expected)
  }

  func testFrameWithNullMemberKeepsTheReadableEdgesWithoutCrashing() {
    // The guest sends a non-finite frame member as JSON null (arriving as NSNull). `CGRectMakeWithDictionaryRepresentation`
    // would raise `-[NSNull _getValue:forType:]` on it, so the null is restored to a non-finite value and the other
    // edges are kept rather than collapsing the rect to `.zero` (a real position for an off-screen element).
    let frameDict = NSMutableDictionary(
      dictionary: CGRectCreateDictionaryRepresentation(CGRect(x: 0, y: 0, width: 10, height: 20)) as NSDictionary
    )
    frameDict["X"] = NSNull()
    let element = AXBridgeSnapshotDecoder.snapshot(fromNode: [AXWire.Node.frame.rawValue: frameDict], pid: 0)

    let frame = element.frame
    XCTAssertFalse(frame.origin.x.isFinite, "the null member is the coordinate the guest could not send")
    XCTAssertEqual(frame.origin.y, 0)
    XCTAssertEqual(frame.size.width, 10)
    XCTAssertEqual(frame.size.height, 20)
  }

  func testRoleMapsElementTypeNumberToReadableName() {
    let element = AXBridgeSnapshotDecoder.snapshot(fromNode: [AXWire.Node.elementType.rawValue: NSNumber(value: 9)], pid: 0)
    XCTAssertEqual(element.role, "Button")
  }

  func testRolePrefersAutomationTypeNameOverElementType() {
    let element = AXBridgeSnapshotDecoder.snapshot(
      fromNode: [
        AXWire.Node.automationType.rawValue: NSNumber(value: 48),
        AXWire.Node.elementType.rawValue: NSNumber(value: 9),
      ], pid: 0)
    XCTAssertEqual(element.role, "StaticText")
  }

  func testRoleFallsBackToRawStringForUnknownElementType() {
    let element = AXBridgeSnapshotDecoder.snapshot(fromNode: [AXWire.Node.elementType.rawValue: NSNumber(value: 9999)], pid: 0)
    XCTAssertEqual(element.role, "9999")
  }

  // `Any` is `XCUIElementType` 0 — a successful lookup, not a miss — so it must not short-circuit past the
  // concrete class name the read already carried.
  func testRoleReportsTheConcreteElementTypeRatherThanAny() {
    let element = AXBridgeSnapshotDecoder.snapshot(
      fromNode: [
        AXWire.Node.automationType.rawValue: NSNumber(value: 0),
        AXWire.Node.elementType.rawValue: "AppRefreshControl",
      ], pid: 0)

    XCTAssertEqual(element.role, "AppRefreshControl")
  }

  // An automation type that resolves to no name (a stringified number) must also lose to the concrete class name.
  func testRoleReportsTheConcreteElementTypeRatherThanAStringifiedAutomationType() {
    let element = AXBridgeSnapshotDecoder.snapshot(
      fromNode: [
        AXWire.Node.automationType.rawValue: NSNumber(value: 9999),
        AXWire.Node.elementType.rawValue: "AppRefreshControl",
      ], pid: 0)

    XCTAssertEqual(element.role, "AppRefreshControl")
  }

  // With nothing better than `Any`, report `Any` — not the literal string "0".
  func testRoleStillReportsAnyWhenThereIsNoConcreteElementType() {
    let element = AXBridgeSnapshotDecoder.snapshot(fromNode: [AXWire.Node.automationType.rawValue: NSNumber(value: 0)], pid: 0)

    XCTAssertEqual(element.role, "Any")
  }

  // The mapping is partial by construction; a bare role number must not reach a caller as an `XCUIElementType` name.
  func testUnidentifiedTranslatorRoleReportsNoType() {
    let element = AXBridgeSnapshotDecoder.snapshot(fromNode: [AXWire.Node.translatorRole.rawValue: NSNumber(value: 99)], pid: 0)
    XCTAssertNil(element.role, "an unidentified role must not surface as a number")
  }

  // A toggle is `CheckBox` and a search field is `TextField`: `Switch` and `SearchField` live in the subrole.
  func testTranslatorRolesAreMappedAcrossTheDecodedTable() {
    let cases: [(Int, String)] = [
      (1, "Application"), (2, "Button"), (3, "CheckBox"), (5, "Group"),
      (6, "Heading"), (14, "StaticText"), (15, "TextField"), (21, "Grid"),
    ]
    for (raw, expected) in cases {
      let element = AXBridgeSnapshotDecoder.snapshot(fromNode: [AXWire.Node.translatorRole.rawValue: NSNumber(value: raw)], pid: 0)
      XCTAssertEqual(element.role, expected, "translator role \(raw)")
    }
  }

  // Both refined names are in the interactable role set; neither bare role is.
  func testASubroleRefinesTheRoleItAccompanies() {
    let toggle = AXBridgeSnapshotDecoder.snapshot(
      fromNode: [
        AXWire.Node.translatorRole.rawValue: NSNumber(value: 3),
        AXWire.Node.translatorSubrole.rawValue: NSNumber(value: 3),
      ], pid: 0)
    XCTAssertEqual(toggle.role, "Switch", "a toggle is a check box with a switch subrole")

    let search = AXBridgeSnapshotDecoder.snapshot(
      fromNode: [
        AXWire.Node.translatorRole.rawValue: NSNumber(value: 15),
        AXWire.Node.translatorSubrole.rawValue: NSNumber(value: 1),
      ], pid: 0)
    XCTAssertEqual(search.role, "SearchField", "a search field is a text field with a search subrole")
  }

  func testAnUnidentifiedSubroleFallsBackToTheRole() {
    let element = AXBridgeSnapshotDecoder.snapshot(
      fromNode: [
        AXWire.Node.translatorRole.rawValue: NSNumber(value: 2),
        AXWire.Node.translatorSubrole.rawValue: NSNumber(value: 99),
      ], pid: 0)
    XCTAssertEqual(element.role, "Button")
  }

  func testXCUIElementTypeOutranksTheTranslatorRole() {
    let element = AXBridgeSnapshotDecoder.snapshot(
      fromNode: [
        AXWire.Node.automationType.rawValue: NSNumber(value: 48),
        AXWire.Node.translatorRole.rawValue: NSNumber(value: 2),
      ], pid: 0)
    XCTAssertEqual(element.role, "StaticText")
  }

  // Only a translator-vocabulary read carries `enabled` (under the reader's own key); every other read must stay
  // unknown rather than report a fabricated `false`.
  func testEnabledIsReadFromATranslatorNodeAndStaysUnknownOnEveryOtherRead() {
    let translator = AXBridgeSnapshotDecoder.snapshot(fromNode: [AXWire.Node.isEnabled.rawValue: false], pid: 7)
    XCTAssertEqual(translator.isEnabled, false, "the translator's enabled answer must be reported")

    let xctest = AXBridgeSnapshotDecoder.snapshot(fromNode: [AXWire.Node.label.rawValue: "General"], pid: 7)
    XCTAssertNil(xctest.isEnabled, "a read carrying no enabled answer must stay unknown")
  }

  // Bits 18 and 21 are `TextEntry` and `IsEditing`: a focused text field.
  func testTraitsAreDecodedFromTheBitmaskEitherVocabularyCarries() {
    let bitmask = NSNumber(value: UInt64(1 << 18 | 1 << 21))
    for key in ["XC_kAXXCAttributeTraits", AXWire.Node.traits.rawValue] {
      let element = AXBridgeSnapshotDecoder.snapshot(fromNode: [key: bitmask], pid: 0)
      XCTAssertEqual(element.traits.map(Set.init), ["TextEntry", "IsEditing"], key)
    }
  }

  func testAbsentAttributesUseSafeDefaults() {
    let element = AXBridgeSnapshotDecoder.snapshot(fromNode: [:], pid: 0)

    XCTAssertNil(element.label)
    XCTAssertNil(element.value)
    XCTAssertNil(element.role)
    XCTAssertNil(element.title)
    XCTAssertNil(element.traits)
    XCTAssertEqual(element.frame, .zero)
    XCTAssertNil(element.isEnabled)
    XCTAssertEqual(element.isHidden, false)
    XCTAssertTrue(element.children.isEmpty)
    XCTAssertNil(element.handle, "a guest read has nothing to act through")
  }
}

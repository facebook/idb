/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// Golden characterization of the accessibility serializer's JSON output over the full default key set
/// (`FBAXKeys.defaultSet`). These pin the exact serialized bytes so a change to the serializer's
/// internal representation cannot silently alter the wire output. In particular they lock:
/// - the value *types* that must survive representation changes: `enabled`/`content_required` bools
///   (not `"true"`/`"false"` strings), `custom_actions` an array, `traits` null-or-array, `pid` a bare
///   int, `AXFrame` a rect string, and `frame` a number dict;
/// - that an absent field is emitted as an explicit `null` with its key retained, not dropped — a
///   deserializing consumer distinguishes JSON `null` from a missing key (JS `null` vs `undefined`);
/// - the `role` (verbatim, e.g. `AXCell`) vs `type` (AX-prefix stripped, e.g. `Cell`) divergence, and
///   the `XCUIElementType` number → name mapping (`9` -> `Button`).
final class FBAccessibilitySerializationTests: XCTestCase {

  // A two-node tree exercising both role sources and present-vs-absent fields:
  // - root carries a numeric `automationType` (9 -> "Button", so role == type), plus a value,
  //   identifier and frame — every present field;
  // - child carries a string `automationType` ("AXCell" -> role "AXCell", type "Cell", pinning the
  //   AX-prefix strip) and omits value/identifier/frame, so those serialize as `null`/zero.
  private static func sampleTree() -> [String: Any] {
    [
      FBRemoteAutomationAXAttribute.label: "root",
      FBRemoteAutomationAXAttribute.value: "on",
      FBRemoteAutomationAXAttribute.identifier: "com.example.root",
      FBRemoteAutomationAXAttribute.automationType: NSNumber(value: 9),
      FBRemoteAutomationAXAttribute.frame:
        CGRectCreateDictionaryRepresentation(CGRect(x: 16, y: 380, width: 370, height: 52)) as NSDictionary,
      FBRemoteAutomationAXAttribute.children: [
        [
          FBRemoteAutomationAXAttribute.label: "child",
          FBRemoteAutomationAXAttribute.automationType: "AXCell",
        ] as [String: Any]
      ],
    ]
  }

  private func serializedJSON(nestedFormat: Bool) throws -> String {
    let elements = FBAXTreeSerialization.describeAllElements(
      fromTree: Self.sampleTree(), keys: FBAXKeys.defaultSet, nestedFormat: nestedFormat, pid: 7
    )
    let response = FBAccessibilityElementsResponse(
      elements: .array(elements)
    )
    let data = try JSONSerialization.data(withJSONObject: response.asDictionary(), options: .sortedKeys)
    return String(decoding: data, as: UTF8.self)
  }

  func testSerializedFlatJSONMatchesGolden() throws {
    XCTAssertEqual(try serializedJSON(nestedFormat: false), Self.expectedFlatJSON)
  }

  func testSerializedNestedJSONMatchesGolden() throws {
    XCTAssertEqual(try serializedJSON(nestedFormat: true), Self.expectedNestedJSON)
  }

  // The profiling collector, coverage grid, and seen-pid set are pure side-channels: they accumulate
  // counts / mark cells / record pids but must not change the serialized node. This invariant is what
  // lets the serializer later split a pure node core from the legacy decorator without a byte change.
  func testNodeDictionaryIsCollectorNeutral() throws {
    let root = FBAXTreeSerialization.buildPlatformElementTree(from: Self.sampleTree(), pid: 7)
    let grid = try XCTUnwrap(FBAccessibilityCoverageGrid(screenBounds: CGRect(x: 0, y: 0, width: 390, height: 844)))
    var elements: [FBAXPlatformElement] = [root]
    elements.append(contentsOf: root.axChildren())
    for element in elements {
      let bare = FBSimulatorAccessibilitySerializer.accessibilityDictionary(
        forElement: element, token: "", keys: FBAXKeys.defaultSet,
        collector: nil, coverageGrid: nil, seenPids: nil, discoveryMethod: "recursive"
      )
      let decorated = FBSimulatorAccessibilitySerializer.accessibilityDictionary(
        forElement: element, token: "", keys: FBAXKeys.defaultSet,
        collector: FBAccessibilityProfilingCollector(), coverageGrid: grid, seenPids: SeenPIDs(),
        discoveryMethod: "recursive"
      )
      XCTAssertEqual(bare, decorated, "profiling/coverage/seen-pid side-channels must not change the node output")
    }
  }

  // An off-screen element (e.g. a SpringBoard icon) can report a non-finite frame coordinate. JSON
  // has no representation for infinity/NaN, so a non-finite value must serialize as null rather than
  // let JSONSerialization throw an uncaught NSException ("Invalid number value (infinite) in JSON
  // write") that terminates the process.
  func testSerializedJSONSanitizesNonFiniteFrame() throws {
    let frameDict = CGRectCreateDictionaryRepresentation(CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 20)) as NSDictionary
    let tree: [String: Any] = [
      FBRemoteAutomationAXAttribute.label: "icon",
      FBRemoteAutomationAXAttribute.frame: frameDict,
    ]
    let elements = FBAXTreeSerialization.describeAllElements(
      fromTree: tree, keys: [.label, .frameDict], nestedFormat: false, pid: 7
    )
    let response = FBAccessibilityElementsResponse(
      elements: .array(elements)
    )
    let data = try JSONSerialization.data(withJSONObject: response.asDictionary(), options: .sortedKeys)
    let json = String(decoding: data, as: UTF8.self)
    XCTAssertTrue(json.contains("\"x\":null"), "non-finite frame x must serialize as null, got: \(json)")
    XCTAssertTrue(json.contains("\"height\":20"), "finite frame values must be preserved, got: \(json)")
  }

  // A tree: root (labeled) → container (unlabeled, no role) → leaf (labeled); plus sibling (labeled).
  private static func filterTree() -> [String: Any] {
    [
      FBRemoteAutomationAXAttribute.label: "root",
      FBRemoteAutomationAXAttribute.children: [
        [
          FBRemoteAutomationAXAttribute.children: [
            [FBRemoteAutomationAXAttribute.label: "leaf"] as [String: Any]
          ]
        ] as [String: Any],
        [FBRemoteAutomationAXAttribute.label: "sibling"] as [String: Any],
      ],
    ]
  }

  private static func labels(_ elements: [FBJSONValue]) -> [String] {
    elements.compactMap { element in
      guard case let .object(fields) = element, case let .string(label)? = fields[FBAXKeys.label.rawValue] else { return nil }
      return label
    }
  }

  func testInteractableFilterDropsUnlabeledContainersFlat() {
    let flat = FBAXTreeSerialization.describeAllElements(
      fromTree: Self.filterTree(), keys: [.label], nestedFormat: false, pid: 7, filter: .interactable
    )
    XCTAssertEqual(Set(Self.labels(flat)), ["root", "leaf", "sibling"], "the unlabeled container is dropped, its leaf kept")
    XCTAssertEqual(flat.count, 3, "only the three labeled elements remain")
  }

  func testInteractableFilterHoistsChildrenOfDroppedContainerNested() throws {
    let nested = FBAXTreeSerialization.describeAllElements(
      fromTree: Self.filterTree(), keys: [.label], nestedFormat: true, pid: 7, filter: .interactable
    )
    guard case let .object(rootNode)? = nested.first, case let .array(children)? = rootNode["children"] else {
      return XCTFail("expected a nested root with a children array")
    }
    XCTAssertEqual(Set(Self.labels(children)), ["leaf", "sibling"], "the dropped container's leaf is hoisted to root")
  }

  func testAllFilterKeepsEveryNode() {
    let flat = FBAXTreeSerialization.describeAllElements(
      fromTree: Self.filterTree(), keys: [.label], nestedFormat: false, pid: 7, filter: .all
    )
    XCTAssertEqual(flat.count, 4, "the default filter keeps the unlabeled container too")
  }

  private static let expectedFlatJSON =
    #"{"elements":[{"AXFrame":"{{16, 380}, {370, 52}}","AXLabel":"root","AXUniqueId":"com.example.root","AXValue":"on","content_required":false,"custom_actions":[],"enabled":true,"frame":{"height":52,"width":370,"x":16,"y":380},"help":null,"pid":7,"role":"Button","role_description":null,"subrole":null,"title":null,"traits":null,"type":"Button"},{"AXFrame":"{{0, 0}, {0, 0}}","AXLabel":"child","AXUniqueId":null,"AXValue":null,"content_required":false,"custom_actions":[],"enabled":true,"frame":{"height":0,"width":0,"x":0,"y":0},"help":null,"pid":7,"role":"AXCell","role_description":null,"subrole":null,"title":null,"traits":null,"type":"Cell"}]}"#

  private static let expectedNestedJSON =
    #"{"elements":[{"AXFrame":"{{16, 380}, {370, 52}}","AXLabel":"root","AXUniqueId":"com.example.root","AXValue":"on","children":[{"AXFrame":"{{0, 0}, {0, 0}}","AXLabel":"child","AXUniqueId":null,"AXValue":null,"children":[],"content_required":false,"custom_actions":[],"enabled":true,"frame":{"height":0,"width":0,"x":0,"y":0},"help":null,"pid":7,"role":"AXCell","role_description":null,"subrole":null,"title":null,"traits":null,"type":"Cell"}],"content_required":false,"custom_actions":[],"enabled":true,"frame":{"height":52,"width":370,"x":16,"y":380},"help":null,"pid":7,"role":"Button","role_description":null,"subrole":null,"title":null,"traits":null,"type":"Button"}]}"#
}

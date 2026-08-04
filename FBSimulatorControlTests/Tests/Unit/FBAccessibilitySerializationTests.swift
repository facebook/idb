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
      FBAXWire.Node.label.rawValue: "root",
      FBAXWire.Node.value.rawValue: "on",
      FBAXWire.Node.identifier.rawValue: "com.example.root",
      FBAXWire.Node.automationType.rawValue: NSNumber(value: 9),
      FBAXWire.Node.frame.rawValue:
        CGRectCreateDictionaryRepresentation(CGRect(x: 16, y: 380, width: 370, height: 52)) as NSDictionary,
      FBAXWire.Node.children.rawValue: [
        [
          FBAXWire.Node.label.rawValue: "child",
          FBAXWire.Node.automationType.rawValue: "AXCell",
        ] as [String: Any]
      ],
    ]
  }

  private func serializedJSON(nestedFormat: Bool) throws -> String {
    let elements = FBAXTreeWalk.describeAllElements(
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

  // The profiling collector and coverage grid are pure side-channels of the node core, and the decorator's
  // seen-pid/is_remote layer adds nothing over the default key set: neither may change the serialized node.
  // This invariant is what lets `nodeDictionary` be the single source of node bytes while
  // `decoratedDictionary` layers on traversal-level concerns.
  func testNodeDictionaryIsCollectorNeutral() throws {
    let root = FBAXTreeWalk.buildPlatformElementTree(from: Self.sampleTree(), pid: 7)
    let grid = try XCTUnwrap(FBAccessibilityCoverageGrid(screenBounds: CGRect(x: 0, y: 0, width: 390, height: 844)))
    var elements: [FBAXPlatformElement] = [root]
    elements.append(contentsOf: root.axChildren())
    for element in elements {
      let bare = FBAXNodeSerializer.nodeDictionary(
        forElement: element, token: "", keys: FBAXKeys.defaultSet,
        collector: nil, coverageGrid: nil
      )
      let instrumented = FBAXNodeSerializer.nodeDictionary(
        forElement: element, token: "", keys: FBAXKeys.defaultSet,
        collector: FBAccessibilityProfilingCollector(), coverageGrid: grid
      )
      XCTAssertEqual(bare, instrumented, "profiling/coverage side-channels must not change the node output")

      let decorated = FBAXNodeSerializer.decoratedDictionary(
        forElement: element, token: "", keys: FBAXKeys.defaultSet,
        collector: FBAccessibilityProfilingCollector(), coverageGrid: grid, seenPids: SeenPIDs(), isRemote: true
      )
      XCTAssertEqual(bare, decorated, "the seen-pid/is_remote decorator must not alter default-set node output")
    }
  }

  // `is_remote` is opt-in (absent from `defaultSet`) and, when requested, is a *bool* recording node
  // provenance — `false` for the main-tree traversal, `true` for remote grid hit-testing — replacing the
  // old discovery-method string. The default set never carries the key, so a default response is
  // byte-identical to the bare node core.
  func testDecoratorTagsIsRemoteProvenanceAsBool() throws {
    let root = FBAXTreeWalk.buildPlatformElementTree(from: Self.sampleTree(), pid: 7)
    var keysWithRemote = FBAXKeys.defaultSet
    keysWithRemote.insert(.isRemote)

    let local = FBAXNodeSerializer.decoratedDictionary(
      forElement: root, token: "", keys: keysWithRemote,
      collector: nil, coverageGrid: nil, seenPids: nil, isRemote: false
    )
    XCTAssertEqual(try XCTUnwrap(local[FBAXKeys.isRemote.rawValue]), .bool(false), "main-tree nodes tag is_remote=false")

    let remote = FBAXNodeSerializer.decoratedDictionary(
      forElement: root, token: "", keys: keysWithRemote,
      collector: nil, coverageGrid: nil, seenPids: nil, isRemote: true
    )
    XCTAssertEqual(try XCTUnwrap(remote[FBAXKeys.isRemote.rawValue]), .bool(true), "remote-discovered nodes tag is_remote=true")

    let defaultSet = FBAXNodeSerializer.decoratedDictionary(
      forElement: root, token: "", keys: FBAXKeys.defaultSet,
      collector: nil, coverageGrid: nil, seenPids: nil, isRemote: true
    )
    XCTAssertNil(defaultSet[FBAXKeys.isRemote.rawValue], "is_remote stays absent unless explicitly requested")
  }

  // An off-screen element (e.g. a SpringBoard icon) can report a non-finite frame coordinate. JSON
  // has no representation for infinity/NaN, so a non-finite value must serialize as null rather than
  // let JSONSerialization throw an uncaught NSException ("Invalid number value (infinite) in JSON
  // write") that terminates the process.
  func testSerializedJSONSanitizesNonFiniteFrame() throws {
    let frameDict = CGRectCreateDictionaryRepresentation(CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 20)) as NSDictionary
    let tree: [String: Any] = [
      FBAXWire.Node.label.rawValue: "icon",
      FBAXWire.Node.frame.rawValue: frameDict,
    ]
    let elements = FBAXTreeWalk.describeAllElements(
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
      FBAXWire.Node.label.rawValue: "root",
      FBAXWire.Node.children.rawValue: [
        [
          FBAXWire.Node.children.rawValue: [
            [FBAXWire.Node.label.rawValue: "leaf"] as [String: Any]
          ]
        ] as [String: Any],
        [FBAXWire.Node.label.rawValue: "sibling"] as [String: Any],
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
    let flat = FBAXTreeWalk.describeAllElements(
      fromTree: Self.filterTree(), keys: [.label], nestedFormat: false, pid: 7, filter: .interactable
    )
    XCTAssertEqual(Set(Self.labels(flat)), ["root", "leaf", "sibling"], "the unlabeled container is dropped, its leaf kept")
    XCTAssertEqual(flat.count, 3, "only the three labeled elements remain")
  }

  func testInteractableFilterHoistsChildrenOfDroppedContainerNested() throws {
    let nested = FBAXTreeWalk.describeAllElements(
      fromTree: Self.filterTree(), keys: [.label], nestedFormat: true, pid: 7, filter: .interactable
    )
    guard case let .object(rootNode)? = nested.first, case let .array(children)? = rootNode["children"] else {
      return XCTFail("expected a nested root with a children array")
    }
    XCTAssertEqual(Set(Self.labels(children)), ["leaf", "sibling"], "the dropped container's leaf is hoisted to root")
  }

  func testAllFilterKeepsEveryNode() {
    let flat = FBAXTreeWalk.describeAllElements(
      fromTree: Self.filterTree(), keys: [.label], nestedFormat: false, pid: 7, filter: .all
    )
    XCTAssertEqual(flat.count, 4, "the default filter keeps the unlabeled container too")
  }

  // Asking for an attribute gets you that attribute: the serializer emits every requested key, using an
  // explicit null when the element has no value for it, and nothing for a key that was not asked for.
  // That is the contract `--key` rests on, and it holds for every key in the schema.
  func testEveryRequestedKeyIsPresentInTheSerializedElement() throws {
    for key in FBAXKeys.allCases {
      let elements = FBAXTreeWalk.describeAllElements(
        fromTree: Self.sampleTree(), keys: [key], nestedFormat: false, pid: 7
      )
      guard case let .object(fields)? = elements.first else {
        return XCTFail("expected a serialized root for --key \(key.rawValue)")
      }
      XCTAssertEqual(Set(fields.keys), [key.rawValue], "--key \(key.rawValue) must emit exactly that key")
    }
  }

  // The corollary: a narrowed read carries only what was asked for, which is what makes `--key` worth
  // passing at all.
  func testUnrequestedKeysAreAbsentFromTheSerializedElement() throws {
    let elements = FBAXTreeWalk.describeAllElements(
      fromTree: Self.sampleTree(), keys: [.label, .title], nestedFormat: false, pid: 7
    )
    guard case let .object(fields)? = elements.first else {
      return XCTFail("expected a serialized root")
    }
    XCTAssertEqual(Set(fields.keys), [FBAXKeys.label.rawValue, FBAXKeys.title.rawValue])
    XCTAssertEqual(fields[FBAXKeys.title.rawValue], .null, "a requested attribute with no value is an explicit null")
  }

  // MARK: - Rendered output (`sortedKeysJSON`)

  /// `sortedKeysJSON()` is the one encoding every CLI and gRPC front-end emits, yet it was reachable in
  /// tests only indirectly through `asDictionary()`. These pin the rendered bytes in each shape a
  /// response takes, so how output is *rendered* cannot change without moving a golden — the envelope
  /// tests below it constrain only what goes into the envelope, not what comes out of the encoder.
  private func renderedJSON(_ response: FBAccessibilityElementsResponse) throws -> String {
    String(decoding: try response.sortedKeysJSON(), as: UTF8.self)
  }

  private func flatElements() -> [FBJSONValue] {
    FBAXTreeWalk.describeAllElements(fromTree: Self.sampleTree(), keys: FBAXKeys.defaultSet, nestedFormat: false, pid: 7)
  }

  func testRenderedFlatJSONMatchesGolden() throws {
    let response = FBAccessibilityElementsResponse(elements: .array(flatElements()))
    XCTAssertEqual(try renderedJSON(response), Self.expectedFlatJSON)
  }

  func testRenderedNestedJSONMatchesGolden() throws {
    let elements = FBAXTreeWalk.describeAllElements(
      fromTree: Self.sampleTree(), keys: FBAXKeys.defaultSet, nestedFormat: true, pid: 7
    )
    let response = FBAccessibilityElementsResponse(elements: .array(elements))
    XCTAssertEqual(try renderedJSON(response), Self.expectedNestedJSON)
  }

  // Every number in the goldens above is integral, and that is a blind spot: JSON writers agree on
  // integral doubles and disagree on everything else. `JSONSerialization` emits the full 17 significant
  // digits (`0.33333333333333331`) where other writers emit the shortest form that round-trips
  // (`0.3333333333333333`). A real frontmost tree is full of such values — sub-point frame edges from
  // hairline separators and layout division — so the exact digits are part of what consumers parse, and
  // a golden with only whole numbers would not notice them changing.
  func testRenderedFractionalValuesKeepFullPrecision() throws {
    let rect = CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 2.0 / 3.0)
    let tree: [String: Any] = [
      FBAXWire.Node.value.rawValue: NSNumber(value: 0.35),
      FBAXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(rect) as NSDictionary,
    ]
    let elements = FBAXTreeWalk.describeAllElements(
      fromTree: tree, keys: [.frameDict, .value], nestedFormat: false, pid: 7
    )
    let response = FBAccessibilityElementsResponse(elements: .array(elements))
    XCTAssertEqual(
      try renderedJSON(response),
      #"{"elements":[{"AXValue":0.34999999999999998,"frame":{"height":0.66666666666666663,"width":0.33333333333333331,"x":0,"y":0}}]}"#
    )
  }

  // `accessibilityValue` is the one attribute the platform reports as an untyped object, and it is not
  // always a scalar. A collection is carried through as a collection rather than flattened to its
  // `String(describing:)` form, which would change what a consumer reads. No golden covered this shape.
  func testCollectionAttributeValuesSurviveAsCollections() throws {
    let arrayTree: [String: Any] = [FBAXWire.Node.value.rawValue: ["alpha", "beta"] as [Any]]
    let arrayElements = FBAXTreeWalk.describeAllElements(
      fromTree: arrayTree, keys: [.value], nestedFormat: false, pid: 7
    )
    XCTAssertEqual(
      try renderedJSON(FBAccessibilityElementsResponse(elements: .array(arrayElements))),
      #"{"elements":[{"AXValue":["alpha","beta"]}]}"#,
      "an array value stays an array"
    )

    let objectTree: [String: Any] = [FBAXWire.Node.value.rawValue: ["min": 0, "max": 10] as [String: Any]]
    let objectElements = FBAXTreeWalk.describeAllElements(
      fromTree: objectTree, keys: [.value], nestedFormat: false, pid: 7
    )
    XCTAssertEqual(
      try renderedJSON(FBAccessibilityElementsResponse(elements: .array(objectElements))),
      #"{"elements":[{"AXValue":{"max":10,"min":0}}]}"#,
      "a dictionary value stays a dictionary"
    )
  }

  // A point or marker read yields a single element, so `elements` is a bare *object* rather than an
  // array — the shape divergence a consumer has to branch on today.
  func testRenderedSingleElementIsAnObjectNotAnArray() throws {
    let response = FBAccessibilityElementsResponse(elements: try XCTUnwrap(flatElements().first))
    XCTAssertEqual(try renderedJSON(response), Self.expectedSingleElementJSON)
  }

  // Profiling and coverage ride in the same envelope beside `elements`, keyed `profile`/`coverage`, and
  // are present only when collected. Durations are held as seconds and emitted as milliseconds.
  func testRenderedEnvelopeCarriesProfileAndCoverage() throws {
    let response = FBAccessibilityElementsResponse(
      elements: .array([]),
      profilingData: Self.sampleProfilingData(),
      frameCoverage: 0.5,
      additionalFrameCoverage: 0.25
    )
    XCTAssertEqual(try renderedJSON(response), Self.expectedProfiledJSON)
  }

  // Coverage without remote-content discovery omits `additional` but keeps `frame`.
  func testRenderedCoverageOmitsAdditionalWhenNotDiscovered() throws {
    let response = FBAccessibilityElementsResponse(elements: .array([]), frameCoverage: 0.25)
    XCTAssertEqual(try renderedJSON(response), #"{"coverage":{"frame":0.25},"elements":[]}"#)
  }

  // The renderer is exactly "the envelope, sorted-keys encoded" — no shaping of its own. This is what
  // makes `asDictionary()` the single definition of the emitted shape, and it is the property that has
  // to be revisited deliberately if rendering ever forks by output format.
  func testRenderedJSONIsTheSortedKeysEncodingOfTheEnvelope() throws {
    let responses: [FBAccessibilityElementsResponse] = [
      FBAccessibilityElementsResponse(elements: .array(flatElements())),
      FBAccessibilityElementsResponse(elements: try XCTUnwrap(flatElements().first)),
      FBAccessibilityElementsResponse(elements: .array([])),
      FBAccessibilityElementsResponse(elements: .array([]), profilingData: Self.sampleProfilingData()),
      FBAccessibilityElementsResponse(elements: .array([]), frameCoverage: 0.5, additionalFrameCoverage: 0.25),
    ]
    for response in responses {
      let expected = try JSONSerialization.data(withJSONObject: response.asDictionary(), options: .sortedKeys)
      XCTAssertEqual(try response.sortedKeysJSON(), expected, "rendering must not reshape \(response)")
    }
  }

  // Fixed, exactly-representable durations so the millisecond conversion has a stable byte form.
  private static func sampleProfilingData() -> FBAccessibilityProfilingData {
    FBAccessibilityProfilingData(
      elementCount: 2,
      attributeFetchCount: 3,
      xpcCallCount: 4,
      translationDuration: 0.5,
      elementConversionDuration: 0.25,
      serializationDuration: 0.125,
      totalXPCDuration: 0.0625,
      fetchedKeys: []
    )
  }

  private static let expectedSingleElementJSON =
    #"{"elements":{"AXFrame":"{{16, 380}, {370, 52}}","AXLabel":"root","AXUniqueId":"com.example.root","AXValue":"on","content_required":false,"custom_actions":[],"enabled":true,"frame":{"height":52,"width":370,"x":16,"y":380},"help":null,"pid":7,"role":"Button","role_description":null,"subrole":null,"title":null,"traits":null,"type":"Button"}}"#

  private static let expectedProfiledJSON =
    #"{"coverage":{"additional":0.25,"frame":0.5},"elements":[],"profile":{"attribute_fetch_count":3,"element_conversion_duration_ms":250,"element_count":2,"serialization_duration_ms":125,"total_xpc_duration_ms":62.5,"translation_duration_ms":500,"xpc_call_count":4}}"#

  private static let expectedFlatJSON =
    #"{"elements":[{"AXFrame":"{{16, 380}, {370, 52}}","AXLabel":"root","AXUniqueId":"com.example.root","AXValue":"on","content_required":false,"custom_actions":[],"enabled":true,"frame":{"height":52,"width":370,"x":16,"y":380},"help":null,"pid":7,"role":"Button","role_description":null,"subrole":null,"title":null,"traits":null,"type":"Button"},{"AXFrame":"{{0, 0}, {0, 0}}","AXLabel":"child","AXUniqueId":null,"AXValue":null,"content_required":false,"custom_actions":[],"enabled":true,"frame":{"height":0,"width":0,"x":0,"y":0},"help":null,"pid":7,"role":"AXCell","role_description":null,"subrole":null,"title":null,"traits":null,"type":"Cell"}]}"#

  private static let expectedNestedJSON =
    #"{"elements":[{"AXFrame":"{{16, 380}, {370, 52}}","AXLabel":"root","AXUniqueId":"com.example.root","AXValue":"on","children":[{"AXFrame":"{{0, 0}, {0, 0}}","AXLabel":"child","AXUniqueId":null,"AXValue":null,"children":[],"content_required":false,"custom_actions":[],"enabled":true,"frame":{"height":0,"width":0,"x":0,"y":0},"help":null,"pid":7,"role":"AXCell","role_description":null,"subrole":null,"title":null,"traits":null,"type":"Cell"}],"content_required":false,"custom_actions":[],"enabled":true,"frame":{"height":52,"width":370,"x":16,"y":380},"help":null,"pid":7,"role":"Button","role_description":null,"subrole":null,"title":null,"traits":null,"type":"Button"}]}"#
}

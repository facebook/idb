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
      elements: .tree(elements)
    )
    let data = try response.legacyJSONData()
    return String(decoding: data, as: UTF8.self)
  }

  func testSerializedFlatJSONMatchesGolden() throws {
    XCTAssertEqual(try serializedJSON(nestedFormat: false), Self.expectedFlatJSON)
  }

  func testSerializedNestedJSONMatchesGolden() throws {
    XCTAssertEqual(try serializedJSON(nestedFormat: true), Self.expectedNestedJSON)
  }

  // The profiling collector is a pure side-channel of the node core, and the decorator's
  // seen-pid/is_remote layer adds nothing over the default key set: neither may change the serialized
  // node. This invariant is what lets `nodeElement` be the single source of node bytes while
  // `decoratedElement` layers on traversal-level concerns.
  //
  // The coverage grid used to be a third side-channel here. It is no longer passed to the serializer at
  // all — coverage is computed from the serialized elements — so that half of the invariant is now
  // structural rather than tested.
  func testNodeDictionaryIsCollectorNeutral() throws {
    let root = FBAXTreeWalk.buildPlatformElementTree(from: Self.sampleTree(), pid: 7)
    var elements: [FBAXPlatformElement] = [root]
    elements.append(contentsOf: root.axChildren())
    for element in elements {
      let bare = FBAXNodeSerializer.nodeElement(
        forElement: element, token: "", keys: FBAXKeys.defaultSet, collector: nil
      )
      let instrumented = FBAXNodeSerializer.nodeElement(
        forElement: element, token: "", keys: FBAXKeys.defaultSet,
        collector: FBAccessibilityProfilingCollector()
      )
      XCTAssertEqual(bare, instrumented, "the profiling side-channel must not change the node output")

      let decorated = FBAXNodeSerializer.decoratedElement(
        forElement: element, token: "", keys: FBAXKeys.defaultSet,
        collector: FBAccessibilityProfilingCollector(), seenPids: SeenPIDs(), isRemote: true
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

    let local = FBAXNodeSerializer.decoratedElement(
      forElement: root, token: "", keys: keysWithRemote,
      collector: nil, seenPids: nil, isRemote: false
    )
    XCTAssertEqual(local.isRemote, .some(false), "main-tree nodes tag is_remote=false")

    let remote = FBAXNodeSerializer.decoratedElement(
      forElement: root, token: "", keys: keysWithRemote,
      collector: nil, seenPids: nil, isRemote: true
    )
    XCTAssertEqual(remote.isRemote, .some(true), "remote-discovered nodes tag is_remote=true")

    let defaultSet = FBAXNodeSerializer.decoratedElement(
      forElement: root, token: "", keys: FBAXKeys.defaultSet,
      collector: nil, seenPids: nil, isRemote: true
    )
    XCTAssertNil(defaultSet.isRemote, "is_remote stays absent unless explicitly requested")
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
      elements: .tree(elements)
    )
    let data = try response.legacyJSONData()
    let json = String(decoding: data, as: UTF8.self)
    XCTAssertTrue(json.contains("\"x\":null"), "non-finite frame x must serialize as null, got: \(json)")
    XCTAssertTrue(json.contains("\"height\":20"), "finite frame values must be preserved, got: \(json)")
  }

  /// A frame as the **guest actually sends it** when one coordinate is non-finite.
  ///
  /// The test above builds the frame with a non-finite `NSNumber`, which is the shape the host's own
  /// element reports. It is not the shape that arrives over the wire: the guest sanitizes a non-finite
  /// number to JSON null before serializing (`AccessibilityService.m`, `FBAXBridgeJSONSafeNumber`),
  /// because JSON can represent neither infinity nor NaN.
  private func guestFrameDictionary(nulling member: String, of rect: CGRect) throws -> NSDictionary {
    let representation = try XCTUnwrap(CGRectCreateDictionaryRepresentation(rect) as? [String: Any])
    XCTAssertNotNil(representation[member], "expected \(member) among the frame keys \(representation.keys.sorted())")
    var nulled = representation
    nulled[member] = NSNull()
    return nulled as NSDictionary
  }

  private func serializedFrame(fromGuestFrame frame: NSDictionary) -> FBAccessibilityFrame?? {
    let tree: [String: Any] = [
      FBAXWire.Node.label.rawValue: "icon",
      FBAXWire.Node.frame.rawValue: frame,
    ]
    let elements = FBAXTreeWalk.describeAllElements(
      fromTree: tree, keys: [.label, .frameDict], nestedFormat: false, pid: 7
    )
    return elements.first?.frame
  }

  // The host cannot parse the null the guest sends, and discards the whole rectangle rather than the
  // one member it could not read. `CGRectMakeWithDictionaryRepresentation` sends a number selector to
  // every member, so the parse is guarded by an all-numbers check that a null fails — and the fallback
  // is `.zero`.
  //
  // The cost is not confined to the unreadable edge: the three coordinates the guest *did* send are
  // thrown away with it, so an element that is merely off-screen is reported as sitting at the origin
  // with no size. `FBAccessibilityFrame` carries per-edge optionals precisely so this does not have to
  // happen, and never gets the chance to apply them.
  func testGuestNullFrameMemberCollapsesTheEntireFrame() throws {
    let frame = try guestFrameDictionary(nulling: "X", of: CGRect(x: 5, y: 10, width: 100, height: 200))
    let serialized = try XCTUnwrap(serializedFrame(fromGuestFrame: frame))

    // BUG: the readable edges are discarded along with the unreadable one — flipped in the next commit.
    XCTAssertEqual(serialized?.x, 0, "the null x becomes zero rather than staying unknown")
    XCTAssertEqual(serialized?.y, 0, "and y is lost with it")
    XCTAssertEqual(serialized?.width, 0, "as is the width the guest did send")
    XCTAssertEqual(serialized?.height, 0, "as is the height")
  }

  // The same collapse is what makes a whole-tree read report no screen: the bounds come from the root
  // element's frame, so a root with one unreadable coordinate reports no bounds at all rather than the
  // width and height it did send.
  func testGuestNullFrameMemberOnTheRootLosesTheScreenBounds() throws {
    let tree: [String: Any] = [
      FBAXWire.Node.label.rawValue: "root",
      FBAXWire.Node.frame.rawValue: try guestFrameDictionary(nulling: "X", of: CGRect(x: 0, y: 0, width: 390, height: 844)),
    ]
    // BUG: the root's width and height are readable, yet the screen is reported as unknown — flipped
    // in the next commit.
    XCTAssertNil(FBAXTreeWalk.screenInfo(fromTree: tree), "the whole frame collapsed, so there are no bounds")
  }

  // The same shape as `filterTree`, but with an unlabeled root — an element `.interactable` would drop
  // were it not the one the caller named, which is what makes the target exemption observable.
  private static func unlabeledTargetTree() -> [String: Any] {
    [
      FBAXWire.Node.children.rawValue: [
        [
          FBAXWire.Node.children.rawValue: [
            [FBAXWire.Node.label.rawValue: "leaf"] as [String: Any]
          ]
        ] as [String: Any],
        [FBAXWire.Node.label.rawValue: "sibling"] as [String: Any],
      ]
    ]
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

  private static func labels(_ elements: [FBAccessibilityDocumentElement]) -> [String] {
    elements.compactMap { $0.label ?? nil }
  }

  // A match carrying only a value: `--match-key AXValue` finds it, and `.interactable` would drop it,
  // since it has no label, no identifier and no actionable role.
  private static func valueOnlyMatchTree() -> [String: Any] {
    [
      FBAXWire.Node.value.rawValue: "42",
      FBAXWire.Node.children.rawValue: [
        [FBAXWire.Node.label.rawValue: "leaf"] as [String: Any]
      ],
    ]
  }

  private static func markerMatchResponse(filter: FBAccessibilityElementFilter) throws -> FBAccessibilityElementsResponse {
    // The accessibility backend resolves a marker by descending from the frontmost root, then hands the
    // *match* to a handle that still carries the root's `.frontmostApplication` request. This reproduces
    // that: the request kind says "tree", the element is the match, and `namesTheTarget` is what tells
    // the request the caller asked for this element rather than the tree it was found in.
    let match = FBAXTreeWalk.buildPlatformElementTree(from: Self.valueOnlyMatchTree(), pid: 7)
    var options = FBAccessibilityRequestOptions()
    options.keys = [.label, .value]
    options.filter = filter
    return try FBAXTranslationRequest(kind: .frontmostApplication).run(match, options: options, namesTheTarget: true)
  }

  // MARK: - The ax marker read's shape

  // A marker read resolves one element, so it serializes as one element — the same shape every other
  // backend already returned. It used to serialize as a tree instead, because the match arrives still
  // carrying the frontmost request it was found through, so `elements` was the match plus its flattened
  // subtree and a consumer had to branch on `--api`.
  func testAxMarkerReadSerializesTheMatchAsASingleElement() throws {
    let response = try Self.markerMatchResponse(filter: .all)
    guard case let .single(element) = response.elements else {
      return XCTFail("a marker read yields one element, got \(response.elements)")
    }
    XCTAssertEqual(element.value ?? nil, .string("42"), "the element reported is the match itself")
    XCTAssertNil(element.children ?? nil, "a flat read carries no children key")
  }

  // And because it is a named element rather than a node of a walk, the filter cannot drop it. It used
  // to be able to: `--filter interactable` would remove the very element the caller named and hoist its
  // descendants into its place.
  func testAxMarkerMatchSurvivesTheFilterThatWouldDropIt() throws {
    let response = try Self.markerMatchResponse(filter: .interactable)
    guard case let .single(element) = response.elements else {
      return XCTFail("a marker read yields one element, got \(response.elements)")
    }
    XCTAssertEqual(
      element.value ?? nil, .string("42"),
      "the match has no label, no identifier and no actionable role, yet is reported because it was named"
    )
  }

  /// Serializes the filter fixture and narrows it the way a read does — walk everything, then keep what
  /// the filter keeps.
  private static func filtered(
    _ filter: FBAccessibilityElementFilter, nestedFormat: Bool
  ) -> [FBAccessibilityDocumentElement] {
    let walked = FBAXTreeWalk.describeAllElements(
      fromTree: filterTree(), keys: [.label, .uniqueID, .role], nestedFormat: nestedFormat, pid: 7
    )
    return filter.apply(to: walked)
  }

  func testInteractableFilterDropsUnlabeledContainersFlat() {
    let flat = Self.filtered(.interactable, nestedFormat: false)
    XCTAssertEqual(Set(Self.labels(flat)), ["root", "leaf", "sibling"], "the unlabeled container is dropped, its leaf kept")
    XCTAssertEqual(flat.count, 3, "only the three labeled elements remain")
  }

  func testInteractableFilterHoistsChildrenOfDroppedContainerNested() throws {
    let nested = Self.filtered(.interactable, nestedFormat: true)
    guard let children = nested.first?.children else {
      return XCTFail("expected a nested root with a children array")
    }
    XCTAssertEqual(Set(Self.labels(children)), ["leaf", "sibling"], "the dropped container's leaf is hoisted to root")
  }

  // A flat read carries no `children` key, and filtering it must not grow one — the filter narrows a
  // list, it does not re-shape it.
  func testFilteringAFlatReadDoesNotIntroduceChildren() {
    for element in Self.filtered(.interactable, nestedFormat: false) {
      XCTAssertNil(element.children, "a filtered flat element stays flat")
    }
  }

  func testAllFilterKeepsEveryNode() {
    let flat = Self.filtered(.all, nestedFormat: false)
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
      let rendered = try XCTUnwrap(elements.first).legacyObject()
      XCTAssertEqual(Set(rendered.keys), [key.rawValue], "--key \(key.rawValue) must emit exactly that key")
    }
  }

  // The corollary: a narrowed read carries only what was asked for, which is what makes `--key` worth
  // passing at all.
  func testUnrequestedKeysAreAbsentFromTheSerializedElement() throws {
    let elements = FBAXTreeWalk.describeAllElements(
      fromTree: Self.sampleTree(), keys: [.label, .title], nestedFormat: false, pid: 7
    )
    let rendered = try XCTUnwrap(elements.first).legacyObject()
    XCTAssertEqual(Set(rendered.keys), [FBAXKeys.label.rawValue, FBAXKeys.title.rawValue])
    XCTAssertTrue(rendered[FBAXKeys.title.rawValue] is NSNull, "a requested attribute with no value is an explicit null")
  }

  // MARK: - Rendered output (`formattedOutputJSON`)

  /// `formattedOutputJSON` is the one encoding every CLI and gRPC front-end emits. These pin the
  /// rendered bytes in each shape a response takes, so how output is *rendered* cannot change without
  /// moving a golden — the envelope tests constrain only what goes into the envelope, not what comes
  /// out of the encoder.
  private func renderedJSON(
    _ response: FBAccessibilityElementsResponse,
    format: FBAccessibilityOutputFormat = .default
  ) throws -> String {
    String(decoding: try response.formattedOutputJSON(format: format), as: UTF8.self)
  }

  private func flatElements() -> [FBAccessibilityDocumentElement] {
    FBAXTreeWalk.describeAllElements(fromTree: Self.sampleTree(), keys: FBAXKeys.defaultSet, nestedFormat: false, pid: 7)
  }

  func testRenderedFlatJSONMatchesGolden() throws {
    let response = FBAccessibilityElementsResponse(elements: .tree(flatElements()))
    XCTAssertEqual(try renderedJSON(response), Self.expectedFlatJSON)
  }

  func testRenderedNestedJSONMatchesGolden() throws {
    let elements = FBAXTreeWalk.describeAllElements(
      fromTree: Self.sampleTree(), keys: FBAXKeys.defaultSet, nestedFormat: true, pid: 7
    )
    let response = FBAccessibilityElementsResponse(elements: .tree(elements))
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
    let response = FBAccessibilityElementsResponse(elements: .tree(elements))
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
      try renderedJSON(FBAccessibilityElementsResponse(elements: .tree(arrayElements))),
      #"{"elements":[{"AXValue":["alpha","beta"]}]}"#,
      "an array value stays an array"
    )

    let objectTree: [String: Any] = [FBAXWire.Node.value.rawValue: ["min": 0, "max": 10] as [String: Any]]
    let objectElements = FBAXTreeWalk.describeAllElements(
      fromTree: objectTree, keys: [.value], nestedFormat: false, pid: 7
    )
    XCTAssertEqual(
      try renderedJSON(FBAccessibilityElementsResponse(elements: .tree(objectElements))),
      #"{"elements":[{"AXValue":{"max":10,"min":0}}]}"#,
      "a dictionary value stays a dictionary"
    )
  }

  // A null *inside* a collection value is a member of that collection, so it has to survive as JSON
  // `null`. It is a distinct case from a null value at the top level, which the element's own optional
  // already carries — a classifier that reports "no value" for both collapses the two, and the nested
  // one has nowhere else to go but a placeholder string. The collection goldens above are all
  // null-free, so nothing catches that.
  func testNullInsideACollectionAttributeValueStaysNull() throws {
    let tree: [String: Any] = [FBAXWire.Node.value.rawValue: ["alpha", NSNull(), "beta"] as [Any]]
    let elements = FBAXTreeWalk.describeAllElements(
      fromTree: tree, keys: [.value], nestedFormat: false, pid: 7
    )
    XCTAssertEqual(
      try renderedJSON(FBAccessibilityElementsResponse(elements: .tree(elements))),
      #"{"elements":[{"AXValue":["alpha",null,"beta"]}]}"#,
      "a null element of an array value is null, not a stringified placeholder"
    )
  }

  // A point or marker read yields a single element, so `elements` is a bare *object* rather than an
  // array — the shape divergence a consumer has to branch on today.
  func testRenderedSingleElementIsAnObjectNotAnArray() throws {
    let response = FBAccessibilityElementsResponse(elements: .single(try XCTUnwrap(flatElements().first)))
    XCTAssertEqual(try renderedJSON(response), Self.expectedSingleElementJSON)
  }

  // Profiling and coverage are reported by `complete` alone. The legacy envelope's bytes are frozen, so
  // collecting either leaves it untouched rather than growing a key onto it.
  func testProfileAndCoverageAppearOnlyInTheCompleteFormat() throws {
    let response = FBAccessibilityElementsResponse(
      elements: .tree([]),
      profilingData: Self.sampleProfilingData(),
      coverage: FBAccessibilityCoverage(frame: 0.5, walked: 0.5, content: 0.5, leaf: 0.5, additional: 0.25)
    )
    for format: FBAccessibilityOutputFormat in [.default, .nested] {
      XCTAssertEqual(
        try renderedJSON(response, format: format), #"{"elements":[]}"#,
        "\(format.rawValue) must not grow keys for collected data it cannot carry"
      )
    }
    XCTAssertEqual(try renderedJSON(response, format: .complete), Self.expectedProfiledDocumentJSON)
  }

  // `default` and `nested` differ only in the elements the serializer already produced, so both render
  // the same envelope; only `complete` changes the document around them.
  func testDefaultAndNestedRenderTheLegacyEnvelope() throws {
    let response = FBAccessibilityElementsResponse(elements: .tree(flatElements()))
    XCTAssertEqual(try renderedJSON(response, format: .default), Self.expectedFlatJSON)
    XCTAssertEqual(try renderedJSON(response, format: .nested), Self.expectedFlatJSON)

    let nested = FBAccessibilityElementsResponse(
      elements: .tree(
        FBAXTreeWalk.describeAllElements(
          fromTree: Self.sampleTree(), keys: FBAXKeys.defaultSet, nestedFormat: true, pid: 7
        ))
    )
    XCTAssertEqual(try renderedJSON(nested, format: .nested), Self.expectedNestedJSON)
  }

  // Properties of the rendering that can actually fail, rather than a comparison against the expression
  // under test: keys come out sorted, the two legacy formats differ only in the elements handed to them,
  // and `complete` is a different document rather than the same envelope.
  func testRenderedJSONIsSortedAndConsistentAcrossFormats() throws {
    let responses: [FBAccessibilityElementsResponse] = [
      FBAccessibilityElementsResponse(elements: .tree(flatElements())),
      FBAccessibilityElementsResponse(elements: .single(try XCTUnwrap(flatElements().first))),
      FBAccessibilityElementsResponse(elements: .tree([])),
      FBAccessibilityElementsResponse(elements: .tree([]), profilingData: Self.sampleProfilingData()),
      FBAccessibilityElementsResponse(elements: .tree([]), coverage: FBAccessibilityCoverage(frame: 0.5, walked: 0.5, content: 0.5, leaf: 0.5, additional: 0.25)),
    ]
    for response in responses {
      // `default` and `nested` differ only in what the serializer already produced, so for one set of
      // elements they must render identically.
      XCTAssertEqual(
        try response.formattedOutputJSON(format: .default),
        try response.formattedOutputJSON(format: .nested),
        "the legacy formats differ in their elements, not in their envelope"
      )

      for format: FBAccessibilityOutputFormat in [.default, .nested, .complete] {
        let rendered = String(decoding: try response.formattedOutputJSON(format: format), as: UTF8.self)
        let keys = Self.topLevelKeys(of: rendered)
        XCTAssertEqual(keys, keys.sorted(), "\(format.rawValue) must emit sorted keys, got \(keys)")
      }

      XCTAssertNotEqual(
        try response.formattedOutputJSON(format: .complete),
        try response.formattedOutputJSON(format: .default),
        "complete is a document, not the legacy envelope"
      )
    }
  }

  /// The top-level keys in emission order, read off the rendered text so the assertion sees what the
  /// encoder actually wrote rather than a re-sorted dictionary.
  private static func topLevelKeys(of json: String) -> [String] {
    var keys: [String] = []
    var depth = 0
    var index = json.startIndex
    var inString = false
    var escaped = false
    var current = ""
    while index < json.endIndex {
      let character = json[index]
      if escaped {
        current.append(character)
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "\"" {
        if inString, depth == 1 {
          let after = json[json.index(after: index)...].first { !$0.isWhitespace }
          if after == ":" { keys.append(current) }
        }
        inString.toggle()
        current = ""
      } else if inString {
        current.append(character)
      } else if character == "{" || character == "[" {
        depth += 1
      } else if character == "}" || character == "]" {
        depth -= 1
      }
      index = json.index(after: index)
    }
    return keys
  }

  // An empty hit-test is a successful result, not a failure, and it stays parseable the same way as an
  // occupied one: the legacy sentinel under the legacy formats, an ordinary document under `complete`.
  func testEmptyHitTestRendersInEveryFormat() throws {
    let backend = FBUIAutomationBackend.axBridge(persistence: .persistent, frontmostMethod: .centerPoint)
    func rendered(_ format: FBAccessibilityOutputFormat) throws -> String {
      let data = try FBAccessibilityElementsResponse.emptyOutputJSON(
        format: format, backend: backend, target: .point(CGPoint(x: 5, y: 6))
      )
      return String(decoding: data, as: UTF8.self)
    }
    for format: FBAccessibilityOutputFormat in [.default, .nested] {
      XCTAssertEqual(try rendered(format), #"{"elements":null}"#, "the legacy empty sentinel is unchanged")
    }
    XCTAssertEqual(
      try rendered(.complete),
      #"{"backend":"axbridge-persistent","coverage":null,"elements":[],"modal":null,"profile":null,"screen":null,"target":{"kind":"point","match_key":null,"pid":null,"value":null,"x":5,"y":6},"truncated":false}"#
    )
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

  // MARK: - Serialized value types

  /// The rendered element, parsed back — what a consumer actually receives.
  ///
  /// These assert the *JSON* type of each attribute rather than the serializer's internal one, so they
  /// keep their meaning across a change of representation: that is the point of pinning them.
  private func renderedElement(keys: Set<FBAXKeys>, tree: [String: Any] = FBAccessibilitySerializationTests.sampleTree()) throws -> [String: Any] {
    let elements = FBAXTreeWalk.describeAllElements(fromTree: tree, keys: keys, nestedFormat: false, pid: 7)
    let response = FBAccessibilityElementsResponse(elements: .tree(elements))
    let rendered = try response.legacyEnvelopeObject()["elements"] as? [[String: Any]]
    return try XCTUnwrap(rendered?.first)
  }

  // The byte goldens cover two key sets. These pin the *type* each attribute is emitted as, which is
  // what a change of internal representation is most likely to get subtly wrong: a bool becoming
  // `"true"`, an integer widening to a double, a null collapsing into a missing key.
  func testSerializedAttributeTypesArePinnedPerKey() throws {
    let element = try renderedElement(keys: Set(FBAXKeys.allCases))

    // Strings, present and absent — an absent one is null, never a missing key or an empty string.
    XCTAssertEqual(element[FBAXKeys.label.rawValue] as? String, "root")
    XCTAssertEqual(element[FBAXKeys.uniqueID.rawValue] as? String, "com.example.root")
    XCTAssertEqual(element[FBAXKeys.value.rawValue] as? String, "on")
    for absent: FBAXKeys in [.title, .help, .roleDescription, .subrole, .placeholder] {
      XCTAssertTrue(element[absent.rawValue] is NSNull, "\(absent.rawValue) must be an explicit null")
      XCTAssertNotNil(element.index(forKey: absent.rawValue), "\(absent.rawValue) must keep its key")
    }

    // Bools stay bools rather than becoming their string spellings or 0/1.
    for flag: FBAXKeys in [.enabled, .contentRequired, .expanded, .hidden, .focused] {
      let value = try XCTUnwrap(element[flag.rawValue] as? NSNumber, "\(flag.rawValue) must be present")
      XCTAssertEqual(CFGetTypeID(value), CFBooleanGetTypeID(), "\(flag.rawValue) must be a JSON bool")
    }

    // pid is an integer, not a double and not a string.
    let pid = try XCTUnwrap(element[FBAXKeys.pid.rawValue] as? NSNumber)
    XCTAssertEqual(String(cString: pid.objCType), "q", "pid must be an integer")
    XCTAssertEqual(pid.int64Value, 7)

    // Arrays stay arrays; `traits` is null-or-array and is null on this element.
    XCTAssertEqual(element[FBAXKeys.customActions.rawValue] as? [String], [])
    XCTAssertTrue(element[FBAXKeys.traits.rawValue] is NSNull)

    // The two frame representations are different types, which is why one of them is redundant.
    XCTAssertEqual(element[FBAXKeys.frame.rawValue] as? String, "{{16, 380}, {370, 52}}")
    let frame = try XCTUnwrap(element[FBAXKeys.frameDict.rawValue] as? [String: Double])
    XCTAssertEqual(frame, ["x": 16, "y": 380, "width": 370, "height": 52])

    // `role` is the raw spelling and `type` the normalized one; both strings.
    XCTAssertEqual(element[FBAXKeys.role.rawValue] as? String, "Button")
    XCTAssertEqual(element[FBAXKeys.type.rawValue] as? String, "Button")
  }

  // The child carries a string automationType, where role and type genuinely diverge.
  func testRawRoleAndNormalizedTypeDivergeOnTheChild() throws {
    let elements = FBAXTreeWalk.describeAllElements(
      fromTree: Self.sampleTree(), keys: [.role, .type], nestedFormat: false, pid: 7
    )
    let response = FBAccessibilityElementsResponse(elements: .tree(elements))
    let child = try XCTUnwrap((try response.legacyEnvelopeObject()["elements"] as? [[String: Any]])?.last)
    XCTAssertEqual(child[FBAXKeys.role.rawValue] as? String, "AXCell", "role keeps the AX prefix")
    XCTAssertEqual(child[FBAXKeys.type.rawValue] as? String, "Cell", "type strips it")
  }

  // A non-finite coordinate has no JSON form, so each edge degrades independently to null while the
  // finite ones survive.
  func testNonFiniteFrameEdgesDegradeIndependently() throws {
    let rect = CGRect(x: CGFloat.infinity, y: 0, width: CGFloat.nan, height: 20)
    let tree: [String: Any] = [
      FBAXWire.Node.label.rawValue: "icon",
      FBAXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(rect) as NSDictionary,
    ]
    let element = try renderedElement(keys: [.frameDict], tree: tree)
    let frame = try XCTUnwrap(element[FBAXKeys.frameDict.rawValue] as? [String: Any])
    XCTAssertTrue(frame["x"] is NSNull, "an infinite edge renders as null")
    XCTAssertTrue(frame["width"] is NSNull, "a NaN edge renders as null")
    XCTAssertEqual(frame["y"] as? Double, 0, "a finite edge survives")
    XCTAssertEqual(frame["height"] as? Double, 20)
  }

  // Nesting is a `children` array on each node, all the way down, and a leaf carries an empty one rather
  // than omitting the key. A flat read carries no `children` key at all.
  func testNestedChildrenShapeIsPinnedAtDepth() throws {
    let nested = FBAXTreeWalk.describeAllElements(
      fromTree: Self.sampleTree(), keys: [.label], nestedFormat: true, pid: 7
    )
    let response = FBAccessibilityElementsResponse(elements: .tree(nested))
    let root = try XCTUnwrap((try response.legacyEnvelopeObject()["elements"] as? [[String: Any]])?.first)
    XCTAssertEqual(root[FBAXKeys.label.rawValue] as? String, "root")
    let children = try XCTUnwrap(root["children"] as? [[String: Any]])
    let child = try XCTUnwrap(children.first)
    XCTAssertEqual(child[FBAXKeys.label.rawValue] as? String, "child")
    XCTAssertEqual((child["children"] as? [Any])?.count, 0, "a leaf carries an empty children array")

    let flat = try renderedElement(keys: [.label])
    XCTAssertNil(flat["children"], "a flat read carries no children key")
  }

  // The legacy formats are untouched by that normalization: a flat read still carries no `children` key,
  // which is what their consumers already parse.
  func testLegacyFormatsStillOmitChildrenForAFlatRead() throws {
    let flat = FBAXTreeWalk.describeAllElements(
      fromTree: Self.sampleTree(), keys: [.label], nestedFormat: false, pid: 7
    )
    let response = FBAccessibilityElementsResponse(elements: .single(try XCTUnwrap(flat.first)))
    XCTAssertEqual(try renderedJSON(response), #"{"elements":{"AXLabel":"root"}}"#)
  }

  // MARK: - Non-finite geometry in the complete document

  // An off-screen element can report a non-finite frame, and the root frame is where screen bounds come
  // from. JSON cannot represent one, and the document encoder refuses it outright — so an unrepresentable
  // bound has to become "unknown" at construction rather than failing the whole read.
  func testNonFiniteScreenBoundsAreReportedAsUnknownRatherThanFailing() throws {
    XCTAssertNil(FBAccessibilityScreenInfo(width: .infinity, height: 844), "a non-finite bound is not a screen")
    XCTAssertNil(FBAccessibilityScreenInfo(width: 390, height: .nan))
    XCTAssertNotNil(FBAccessibilityScreenInfo(width: 390, height: 844))

    let response = FBAccessibilityElementsResponse(
      elements: .tree([]), screen: FBAccessibilityScreenInfo(width: .infinity, height: 844)
    )
    let document = documentObject(response)
    XCTAssertTrue(document["screen"] is NSNull, "unknown bounds are null, and the read still renders")
    XCTAssertEqual(Set(document.keys).count, 8, "the document keeps its fixed key set")
  }

  // The same hazard on a hit-tested coordinate: `ui shell` parses one with `Double(_:)`, which accepts
  // "inf", and that must not take the whole render down either.
  func testNonFinitePointTargetRendersAsNull() throws {
    let response = FBAccessibilityElementsResponse(
      elements: .tree([]), target: .point(CGPoint(x: CGFloat.infinity, y: 400))
    )
    let target = try XCTUnwrap(documentObject(response)["target"] as? [String: Any])
    XCTAssertTrue(target["x"] is NSNull, "an unrepresentable coordinate is null")
    XCTAssertEqual(target["y"] as? Double, 400, "the representable one survives")
    XCTAssertEqual(target["kind"] as? String, "point")
  }

  // MARK: - The `complete` document

  /// The document encoded exactly as a caller receives it.
  private func documentJSON(_ response: FBAccessibilityElementsResponse) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return String(decoding: try encoder.encode(response.document), as: UTF8.self)
  }

  /// The document as untyped Foundation — what a consumer parsing the emitted JSON sees. Test-local, so
  /// the production path never hands out an `Any`.
  private func documentObject(_ response: FBAccessibilityElementsResponse) -> [String: Any] {
    guard let data = try? JSONEncoder().encode(response.document),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [:]
    }
    return object
  }

  private func documentKeys(_ response: FBAccessibilityElementsResponse) -> Set<String> {
    Set(documentObject(response).keys)
  }

  // MARK: - The element filter on a single-element read

  // Both halves of the rule now hold.
  //
  // The target is never filtered — a caller who named an element by point or marker asked about that
  // element, so it is built directly rather than taken from a walk over it. That already held, and the
  // fixture makes it observable: the target here would not survive `.interactable` were it any other
  // node, carrying no label, no identifier and no actionable role.
  //
  // Its descendants are now walked with the caller's filter, as a whole-tree read already did. They
  // used to be walked with it hard-coded off, so `describe <x> <y> --nested --filter interactable`
  // returned every one of them while `describe-all --filter interactable` pruned them.
  func testSingleElementReadKeepsTheTargetAndFiltersItsDescendants() throws {
    let element = FBAXTreeWalk.buildPlatformElementTree(from: Self.unlabeledTargetTree(), pid: 7)
    var options = FBAccessibilityRequestOptions()
    options.keys = [.label]
    options.filter = .interactable
    options.format = .nested

    let response = try FBAXTranslationRequest(kind: .point(.zero)).run(element, options: options)
    guard case let .single(target) = response.elements else {
      return XCTFail("a point read yields one element, got \(response.elements)")
    }
    XCTAssertNil(
      target.label ?? nil,
      "the unlabeled target is reported as itself, not replaced by a labeled descendant"
    )
    XCTAssertEqual(
      Set((target.children ?? []).compactMap { $0.label ?? nil }), ["leaf", "sibling"],
      "the unlabeled container is dropped and its labeled leaf hoisted, as a whole-tree read already did"
    )
    XCTAssertEqual(target.children?.count, 2, "two children either way — only which two changes")
  }

  // MARK: - Children reporting

  // `complete` reports `children` on every element, whatever the read walked. It used to follow the
  // walk instead: a flat read — the shape a guest-backed hit-test produces, since those resolve one
  // node and never look further — omitted the key entirely, so `describe <x> <y> --format complete`
  // described the same element with a different key set depending on `--api`. That is the one thing
  // the document's fixed key set exists to rule out.
  func testCompleteAlwaysReportsChildrenWhateverTheReadWalked() throws {
    let flat = FBAXTreeWalk.describeAllElements(
      fromTree: Self.sampleTree(), keys: [.label], nestedFormat: false, pid: 7
    )
    XCTAssertNil(try XCTUnwrap(flat.first).children, "the model still records that nothing was walked")

    let response = FBAccessibilityElementsResponse(elements: .single(try XCTUnwrap(flat.first)))
    let element = try XCTUnwrap((documentObject(response)["elements"] as? [[String: Any]])?.first)
    XCTAssertEqual(
      (element["children"] as? [Any])?.count, 0,
      "the key is reported regardless, empty where nothing was walked"
    )

    let nested = FBAXTreeWalk.describeAllElements(
      fromTree: Self.sampleTree(), keys: [.label], nestedFormat: true, pid: 7
    )
    let nestedResponse = FBAccessibilityElementsResponse(elements: .tree(nested))
    let root = try XCTUnwrap((documentObject(nestedResponse)["elements"] as? [[String: Any]])?.first)
    let children = try XCTUnwrap(root["children"] as? [[String: Any]])
    XCTAssertEqual(children.count, 1, "a read that walked a subtree still reports what it walked")
    XCTAssertEqual((children[0]["children"] as? [Any])?.count, 0, "and its leaf reports an empty array")
  }

  // The clean-schema assertions below read the document as untyped Foundation, which is what a consumer
  // parsing the emitted JSON actually sees — the production path stays typed end to end.

  // The clean schema re-spells the AX-prefixed holdovers and drops the two attributes that merely
  // restate another (`AXFrame` for the `frame` object, raw `role` for the normalized `type`).
  func testCompleteElementsUseTheCleanSchema() throws {
    let elements = FBAXTreeWalk.describeAllElements(
      fromTree: Self.sampleTree(), keys: FBAXKeys.defaultSet, nestedFormat: true, pid: 7
    )
    let response = FBAccessibilityElementsResponse(elements: .tree(elements))
    let document = try XCTUnwrap(documentObject(response)["elements"] as? [[String: Any]])
    let root = try XCTUnwrap(document.first)

    XCTAssertEqual(root["label"] as? String, "root", "AXLabel is re-spelled")
    XCTAssertEqual(root["value"] as? String, "on", "AXValue is re-spelled")
    XCTAssertEqual(root["identifier"] as? String, "com.example.root", "AXUniqueId is re-spelled")
    XCTAssertEqual(root["type"] as? String, "Button", "the normalized role is the canonical type")
    XCTAssertNotNil(root["frame"] as? [String: Any], "the frame object is kept")

    XCTAssertNil(root["AXLabel"], "the legacy spelling is gone")
    XCTAssertNil(root["AXValue"], "the legacy spelling is gone")
    XCTAssertNil(root["AXUniqueId"], "the legacy spelling is gone")
    XCTAssertNil(root["AXFrame"], "the stringified frame is dropped as a duplicate of `frame`")
    XCTAssertNil(root["role"], "the raw role is dropped as a duplicate of `type`")

    // Attributes that carry information `type` does not are kept, with their keys retained even when null.
    for kept in ["role_description", "subrole", "title", "help", "enabled", "custom_actions", "content_required", "pid", "traits"] {
      XCTAssertTrue(root.keys.contains(kept), "\(kept) must survive the clean schema")
    }
  }

  func testCompleteElementsRecurseIntoChildren() throws {
    let elements = FBAXTreeWalk.describeAllElements(
      fromTree: Self.sampleTree(), keys: FBAXKeys.defaultSet, nestedFormat: true, pid: 7
    )
    let response = FBAccessibilityElementsResponse(elements: .tree(elements))
    let document = try XCTUnwrap(documentObject(response)["elements"] as? [[String: Any]])
    let children = try XCTUnwrap(try XCTUnwrap(document.first)["children"] as? [[String: Any]])
    let child = try XCTUnwrap(children.first)
    XCTAssertEqual(child["label"] as? String, "child", "a nested node is normalized too")
    XCTAssertNil(child["AXLabel"], "nesting must not smuggle the legacy spelling through")
    XCTAssertEqual(child["type"] as? String, "Cell")
    XCTAssertNil(child["role"], "the raw AXCell role is dropped at every depth")
  }

  // A single-element read is an object in the legacy envelope; `complete` always presents an array so a
  // consumer never branches on the shape.
  func testCompleteElementsIsAlwaysAnArray() throws {
    let cases: [(String, FBAccessibilityElementPayload, Int)] = [
      ("a whole-tree read", .tree(flatElements()), 2),
      ("a single-element read", .single(try XCTUnwrap(flatElements().first)), 1),
      ("an empty read", .tree([]), 0),
      ("an absent element", .empty, 0),
    ]
    for (name, elements, count) in cases {
      let response = FBAccessibilityElementsResponse(elements: elements)
      let document = documentObject(response)["elements"] as? [Any]
      XCTAssertEqual(document?.count, count, "\(name) must present \(count) element(s) in an array")
    }
  }

  // The document's key set never varies: what a verb or backend cannot supply is an explicit null, so
  // one parser serves every describe verb.
  func testCompleteDocumentKeySetIsFixedAcrossReads() throws {
    let expected: Set<String> = ["elements", "modal", "truncated", "screen", "backend", "target", "profile", "coverage"]
    let bare = FBAccessibilityElementsResponse(elements: .tree([]))
    let full = FBAccessibilityElementsResponse(
      elements: .tree(flatElements()),
      profilingData: Self.sampleProfilingData(),
      coverage: FBAccessibilityCoverage(frame: 0.5, walked: 0.5, content: 0.5, leaf: 0.5, additional: 0.25),
      modal: FBAccessibilityModalInfo(kind: .system, elementType: "SBAlertItemWindow", label: "Allow"),
      truncated: true,
      screen: FBAccessibilityScreenInfo(width: 390, height: 844),
      backend: .axBridge,
      target: .point(CGPoint(x: 10, y: 20))
    )
    XCTAssertEqual(documentKeys(bare), expected, "an empty read still carries every key")
    XCTAssertEqual(documentKeys(full), expected)
  }

  func testCompleteDocumentEmitsAbsentSignalsAsNull() throws {
    let response = FBAccessibilityElementsResponse(elements: .tree([]))
    XCTAssertEqual(
      try documentJSON(response),
      #"{"backend":null,"coverage":null,"elements":[],"modal":null,"profile":null,"screen":null,"target":null,"truncated":false}"#
    )
  }

  func testCompleteDocumentCarriesTheReadsSignals() throws {
    let response = FBAccessibilityElementsResponse(
      elements: .tree([]),
      profilingData: Self.sampleProfilingData(),
      coverage: FBAccessibilityCoverage(frame: 0.5, walked: 0.5, content: 0.5, leaf: 0.5, additional: nil),
      modal: FBAccessibilityModalInfo(kind: .system, elementType: "SBAlertItemWindow", label: "Allow"),
      truncated: true,
      screen: FBAccessibilityScreenInfo(width: 390, height: 844),
      backend: .axBridge,
      target: .marker(value: "General", matchKey: FBAXSearchableKey.label.rawValue)
    )
    let document = documentObject(response)

    XCTAssertEqual(document["backend"] as? String, "axbridge")
    XCTAssertEqual(document["truncated"] as? Bool, true)

    let modal = try XCTUnwrap(document["modal"] as? [String: Any])
    XCTAssertEqual(modal["kind"] as? String, "system")
    XCTAssertEqual(modal["element_type"] as? String, "SBAlertItemWindow")
    XCTAssertEqual(modal["label"] as? String, "Allow")

    let screen = try XCTUnwrap(document["screen"] as? [String: Any])
    XCTAssertEqual(screen["width"] as? Double, 390)
    XCTAssertEqual(screen["coordinate_space"] as? String, "screen")

    // A target keeps every key so the shape does not vary with the verb; only the values differ.
    let target = try XCTUnwrap(document["target"] as? [String: Any])
    XCTAssertEqual(target["kind"] as? String, "marker")
    XCTAssertEqual(target["value"] as? String, "General")
    XCTAssertEqual(target["match_key"] as? String, "AXLabel")
    XCTAssertTrue(target["x"] is NSNull, "a marker has no point, but keeps the key")
    XCTAssertTrue(target["pid"] is NSNull, "a marker has no pid, but keeps the key")

    // Coverage keeps `additional` as null when remote-content discovery found nothing.
    let coverage = try XCTUnwrap(document["coverage"] as? [String: Any])
    XCTAssertEqual(coverage["frame"] as? Double, 0.5)
    XCTAssertTrue(coverage["additional"] is NSNull)

    XCTAssertEqual((document["profile"] as? [String: NSNumber])?["element_count"], NSNumber(value: 2))
  }

  func testCompleteDocumentTargetKindsCarryTheirOwnFields() throws {
    let targets: [(FBAccessibilityTargetDescriptor, String, String, Any?)] = [
      (.frontmost, "frontmost", "pid", nil),
      (.application(pid: 60924), "application", "pid", 60924),
      (.point(CGPoint(x: 10, y: 20)), "point", "x", 10.0),
    ]
    for (target, kind, key, value) in targets {
      let document = documentObject(FBAccessibilityElementsResponse(elements: .tree([]), target: target))
      let emitted = try XCTUnwrap(document["target"] as? [String: Any])
      XCTAssertEqual(emitted["kind"] as? String, kind)
      XCTAssertEqual(
        Set(emitted.keys), ["kind", "pid", "x", "y", "value", "match_key"],
        "every target kind emits the same keys"
      )
      // Compared as numbers rather than by concrete Swift type: a pid is emitted as an integer and a
      // coordinate as a double, and the assertion is about the value, not which width it bridges to.
      switch value {
      case let expected as Int:
        XCTAssertEqual((emitted[key] as? NSNumber)?.intValue, expected)
      case let expected as Double:
        XCTAssertEqual((emitted[key] as? NSNumber)?.doubleValue, expected)
      default:
        XCTAssertTrue(emitted[key] is NSNull, "\(kind) has no \(key), but keeps the key")
      }
    }
  }

  // An attribute that was requested but has no value is `null`; one that was never requested is absent.
  // Collapsing both to `null` would leave a consumer unable to tell "not asked for" from "asked for and
  // empty", and would stop `--key` from trimming the payload it exists to trim.
  func testCompleteElementsOmitUnrequestedAttributesButNullRequestedEmptyOnes() throws {
    // The sample root has a label but no title, so `title` is requested-and-empty here. `complete` is
    // always a tree, so the fixture is read nested.
    let elements = FBAXTreeWalk.describeAllElements(
      fromTree: Self.sampleTree(), keys: [.label, .title], nestedFormat: true, pid: 7
    )
    let response = FBAccessibilityElementsResponse(elements: .tree(elements))
    let root = try XCTUnwrap(documentObject(response)["elements"] as? [[String: Any]]).first ?? [:]

    XCTAssertEqual(root["label"] as? String, "root")
    XCTAssertTrue(root["title"] is NSNull, "a requested attribute with no value stays as an explicit null")
    for unrequested in ["identifier", "type", "frame", "enabled", "pid", "traits", "placeholder", "is_remote"] {
      XCTAssertNil(root[unrequested], "\(unrequested) was not requested, so it must be absent, not null")
    }
    XCTAssertNotNil(root["children"], "a nested read reports its children")
  }

  // Narrowing the key set must actually narrow the payload — that is what --key is for.
  func testCompleteElementsShrinkWithTheRequestedKeySet() throws {
    func keyCount(_ keys: Set<FBAXKeys>) throws -> Int {
      let elements = FBAXTreeWalk.describeAllElements(fromTree: Self.sampleTree(), keys: keys, nestedFormat: true, pid: 7)
      let response = FBAccessibilityElementsResponse(elements: .tree(elements))
      let root = try XCTUnwrap(documentObject(response)["elements"] as? [[String: Any]]).first ?? [:]
      return root.keys.count
    }
    let narrow = try keyCount([.label])
    let wide = try keyCount(FBAXKeys.defaultSet)
    XCTAssertLessThan(narrow, wide, "a narrowed read must emit fewer element keys")
    XCTAssertEqual(narrow, 2, "just `label` plus the nested read's `children`")
  }

  // Whatever a caller asks for comes back. `complete` reports two attributes only through their
  // canonical counterparts, so a request for the deduplicated spelling has to resolve to the one that
  // carries it — otherwise asking for `AXFrame` or `role` would silently yield nothing.
  func testEveryRequestedKeyIsPresentInTheCompleteOutput() throws {
    for key in FBAXKeys.allCases {
      var options = FBAccessibilityRequestOptions(format: .complete)
      options.keys = [key]
      let elements = FBAXTreeWalk.describeAllElements(
        fromTree: Self.sampleTree(), keys: options.serializationKeys, nestedFormat: false, pid: 7
      )
      let response = FBAccessibilityElementsResponse(elements: .tree(elements))
      let root = try XCTUnwrap(documentObject(response)["elements"] as? [[String: Any]]).first ?? [:]
      let expected = Self.completeName(for: key)
      XCTAssertTrue(
        root.keys.contains(expected),
        "--key \(key.rawValue) must yield `\(expected)`, got \(root.keys.sorted())"
      )
    }
  }

  /// The clean-schema key a requested attribute is reported under.
  private static func completeName(for key: FBAXKeys) -> String {
    switch key {
    case .label: return "label"
    case .value: return "value"
    case .uniqueID: return "identifier"
    // The two the schema deduplicates: reported through the attribute that carries them.
    case .frame, .frameDict: return "frame"
    case .role, .type: return "type"
    case .title: return "title"
    case .help: return "help"
    case .enabled: return "enabled"
    case .customActions: return "custom_actions"
    case .roleDescription: return "role_description"
    case .subrole: return "subrole"
    case .contentRequired: return "content_required"
    case .pid: return "pid"
    case .traits: return "traits"
    case .expanded: return "expanded"
    case .placeholder: return "placeholder"
    case .hidden: return "hidden"
    case .focused: return "focused"
    case .isRemote: return "is_remote"
    }
  }

  // An opt-in key is already snake_case, so the clean schema keeps its spelling — but it must still be
  // carried through rather than dropped for not being in the rename table's "renamed" half.
  func testCompleteElementsKeepOptInKeys() throws {
    var keys = FBAXKeys.defaultSet
    keys.insert(.placeholder)
    let elements = FBAXTreeWalk.describeAllElements(fromTree: Self.sampleTree(), keys: keys, nestedFormat: false, pid: 7)
    let response = FBAccessibilityElementsResponse(elements: .tree(elements))
    let document = try XCTUnwrap(documentObject(response)["elements"] as? [[String: Any]])
    XCTAssertTrue(try XCTUnwrap(document.first).keys.contains("placeholder"))
  }

  private static let expectedSingleElementJSON =
    #"{"elements":{"AXFrame":"{{16, 380}, {370, 52}}","AXLabel":"root","AXUniqueId":"com.example.root","AXValue":"on","content_required":false,"custom_actions":[],"enabled":true,"frame":{"height":52,"width":370,"x":16,"y":380},"help":null,"pid":7,"role":"Button","role_description":null,"subrole":null,"title":null,"traits":null,"type":"Button"}}"#

  private static let expectedProfiledDocumentJSON =
    #"{"backend":null,"coverage":{"additional":0.25,"content":0.5,"frame":0.5,"leaf":0.5,"walked":0.5},"elements":[],"modal":null,"profile":{"attribute_fetch_count":3,"element_conversion_duration_ms":250,"element_count":2,"serialization_duration_ms":125,"total_xpc_duration_ms":62.5,"translation_duration_ms":500,"xpc_call_count":4},"screen":null,"target":null,"truncated":false}"#

  private static let expectedFlatJSON =
    #"{"elements":[{"AXFrame":"{{16, 380}, {370, 52}}","AXLabel":"root","AXUniqueId":"com.example.root","AXValue":"on","content_required":false,"custom_actions":[],"enabled":true,"frame":{"height":52,"width":370,"x":16,"y":380},"help":null,"pid":7,"role":"Button","role_description":null,"subrole":null,"title":null,"traits":null,"type":"Button"},{"AXFrame":"{{0, 0}, {0, 0}}","AXLabel":"child","AXUniqueId":null,"AXValue":null,"content_required":false,"custom_actions":[],"enabled":true,"frame":{"height":0,"width":0,"x":0,"y":0},"help":null,"pid":7,"role":"AXCell","role_description":null,"subrole":null,"title":null,"traits":null,"type":"Cell"}]}"#

  private static let expectedNestedJSON =
    #"{"elements":[{"AXFrame":"{{16, 380}, {370, 52}}","AXLabel":"root","AXUniqueId":"com.example.root","AXValue":"on","children":[{"AXFrame":"{{0, 0}, {0, 0}}","AXLabel":"child","AXUniqueId":null,"AXValue":null,"children":[],"content_required":false,"custom_actions":[],"enabled":true,"frame":{"height":0,"width":0,"x":0,"y":0},"help":null,"pid":7,"role":"AXCell","role_description":null,"subrole":null,"title":null,"traits":null,"type":"Cell"}],"content_required":false,"custom_actions":[],"enabled":true,"frame":{"height":52,"width":370,"x":16,"y":380},"help":null,"pid":7,"role":"Button","role_description":null,"subrole":null,"title":null,"traits":null,"type":"Button"}]}"#
}

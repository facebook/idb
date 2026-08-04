/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// Coverage for the axbridge read path that does not require a live simulator: the guest response
/// envelope parsing (`FBAXTreeRead`) and the tree -> shared-serializer integration that makes
/// the axbridge output identical to the testmanagerd backend (both feed `describeAllElements`).
final class FBAXBridgeReadsTests: XCTestCase {

  private func envelope(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
  }

  // MARK: - FBAXTreeRead envelope parsing

  func testParsesTreeFromOkEnvelope() throws {
    let tree: [String: Any] = [
      FBAXWire.Node.label.rawValue: "General",
      FBAXWire.Node.identifier.rawValue: "com.apple.settings.general",
    ]
    let data = try envelope(["ok": true, "tree": tree])
    let parsed = try FBAXTreeRead(wholeTreeResponse: data, pid: 42)
    XCTAssertEqual(parsed.tree[FBAXWire.Node.label.rawValue] as? String, "General")
    XCTAssertEqual(parsed.tree[FBAXWire.Node.identifier.rawValue] as? String, "com.apple.settings.general")
    XCTAssertFalse(parsed.truncated, "a whole-tree read with no truncated flag is a complete tree")
  }

  func testParsesTruncatedFlagWhenGuestReportsAPartialTree() throws {
    // A guest walk cut short by the depth or node bound tags its envelope `truncated: true`, so the
    // conformer can warn the tree is incomplete rather than pass it off as whole.
    let tree: [String: Any] = [FBAXWire.Node.label.rawValue: "root"]
    let data = try envelope(["ok": true, "tree": tree, "truncated": true])
    let parsed = try FBAXTreeRead(wholeTreeResponse: data, pid: 42)
    XCTAssertTrue(parsed.truncated, "the guest's truncation flag must be surfaced to the caller")
  }

  func testSurfacesGuestErrorMessage() throws {
    // An untagged failure (no `error_kind`) is an opaque `guestFailure` carrying the guest's own
    // message, so callers see the real cause.
    let data = try envelope(["ok": false, "error": "the accessibility server is not responding"])
    XCTAssertThrowsError(try FBAXTreeRead(wholeTreeResponse: data, pid: 7)) { error in
      guard case FBAXBridgeError.guestFailure = error else {
        return XCTFail("an untagged failure should be a guestFailure, got: \(error)")
      }
      XCTAssertTrue("\(error)".contains("the accessibility server is not responding"), "unexpected error: \(error)")
    }
  }

  func testApplicationUnavailableErrorKindThrowsTypedCase() throws {
    // A failure tagged `application_unavailable` becomes the typed `FBAXBridgeError.applicationUnavailable`
    // (carrying the pid), which the conformer re-raises as the backend-neutral
    // `FBUIAutomationError.applicationUnavailable` — matching what the remote backend throws for a dead pid.
    let data = try envelope(["ok": false, "error": "no application element for pid 7", "error_kind": "application_unavailable"])
    XCTAssertThrowsError(try FBAXTreeRead(wholeTreeResponse: data, pid: 7)) { error in
      guard case let FBAXBridgeError.applicationUnavailable(pid) = error else {
        return XCTFail("a tagged failure should be applicationUnavailable, got: \(error)")
      }
      XCTAssertEqual(pid, 7)
    }
  }

  func testThrowsOnMalformedResponse() {
    let data = Data("this is not json".utf8)
    XCTAssertThrowsError(try FBAXTreeRead(wholeTreeResponse: data, pid: 1))
  }

  func testThrowsWhenOkButNoTree() throws {
    let data = try envelope(["ok": true])
    XCTAssertThrowsError(try FBAXTreeRead(wholeTreeResponse: data, pid: 1))
  }

  func testThrowsWhenNotOk() throws {
    // `ok` missing/false with no `error` still fails rather than yielding an empty tree.
    let data = try envelope(["tree": [FBAXWire.Node.label.rawValue: "x"]])
    XCTAssertThrowsError(try FBAXTreeRead(wholeTreeResponse: data, pid: 1))
  }

  // MARK: - One error type across backends

  // The point of the unified error: a caller holding `any FBUIAutomation` does not statically know
  // its backend, so "not found" has to be catchable without knowing. One catch clause must handle
  // every backend, and the message must still say which one spoke.
  func testOneCatchClauseHandlesEveryBackend() {
    let backends: [FBUIAutomationBackend] = [.accessibility, .remoteAutomation, .axBridge(persistence: .oneShot, frontmostMethod: .centerPoint), .axBridge(persistence: .persistent, frontmostMethod: .centerPoint)]
    for backend in backends {
      let thrown: Error = FBUIAutomationError.elementNotFound(backend: backend, key: "AXLabel", value: "General")
      guard case let FBUIAutomationError.elementNotFound(caught, key, value) = thrown else {
        return XCTFail("\(backend) did not match the shared case")
      }
      XCTAssertEqual(caught, backend)
      XCTAssertEqual(key, "AXLabel")
      XCTAssertEqual(value, "General")
      let description = (thrown as? LocalizedError)?.errorDescription ?? ""
      XCTAssertTrue(description.contains(backend.displayName), "message should name the backend: \(description)")
      XCTAssertTrue(description.contains("General"), "message should name the marker: \(description)")
    }
  }

  func testEmptyPointErrorCarriesTheAccessibilityHint() {
    // An empty read is most often a missing accessibility server, so the actionable hint rides on the
    // error rather than being re-stated by each backend.
    let error = FBUIAutomationError.noElementAtPoint(backend: .axBridge(persistence: .oneShot, frontmostMethod: .centerPoint), x: 2000, y: 2000)
    XCTAssertTrue(error.description.contains("ApplicationAccessibilityEnabled"), "got: \(error.description)")
  }

  func testValueMismatchIsSeamCatchableAndNamesTheMismatch() {
    // A `tap` value assertion is a fact about the query, not the transport, so it is the neutral
    // `FBUIAutomationError` — catchable by a caller holding `any FBUIAutomation` — and its message
    // names the backend, the key, and both values.
    let thrown: Error = FBUIAutomationError.valueMismatch(
      backend: .accessibility, key: FBAXSearchableKey.value.rawValue, expected: "On", actual: "Off"
    )
    guard case let FBUIAutomationError.valueMismatch(backend, key, expected, actual) = thrown else {
      return XCTFail("value mismatch should match the shared case, got: \(thrown)")
    }
    XCTAssertEqual(backend, .accessibility)
    XCTAssertEqual(key, "AXValue")
    XCTAssertEqual(expected, "On")
    XCTAssertEqual(actual, "Off")
    let description = (thrown as? LocalizedError)?.errorDescription ?? ""
    XCTAssertTrue(description.contains("The accessibility backend"), "message should name the backend: \(description)")
    XCTAssertTrue(description.contains("AXValue"), "message should name the key: \(description)")
    XCTAssertTrue(description.contains("On") && description.contains("Off"), "message should name both values: \(description)")
  }

  // MARK: - Marker matching agrees with the accessibility backend

  // The accessibility backend walks the live tree and matches a marker by substring, so the
  // serialized-tree matcher the XCUI-grade backends use must do the same: a marker has to resolve to
  // the same element whichever backend serves the read, or `--api` silently changes what `tap General`
  // hits. This pins the substring contract stated on FBAccessibilityElementQuery.marker.
  func testMarkerMatchesBySubstring() throws {
    let elements = FBAXTreeSerialization.describeAllElements(
      fromTree: [
        FBAXWire.Node.label.rawValue: "root",
        FBAXWire.Node.children.rawValue: [
          [FBAXWire.Node.label.rawValue: "General Settings", FBAXWire.Node.children.rawValue: [[String: Any]]()] as [String: Any]
        ],
      ],
      keys: FBAXKeys.defaultSet, nestedFormat: false, pid: 1
    )
    let match = FBAXTreeSerialization.matchingElement(inElements: elements, markerValue: "General", key: .label)
    guard case let .object(fields)? = match, case let .string(label)? = fields[FBAXSearchableKey.label.rawValue] else {
      return XCTFail("a substring marker must match, got: \(String(describing: match))")
    }
    XCTAssertEqual(label, "General Settings")
  }

  func testMarkerFrameCentreMatchesBySubstring() throws {
    // `tap`/`wait`/`set-value` resolve through frameCenter, so it must use the same predicate as the
    // describe matcher — otherwise a marker could be describable but not tappable.
    let elements = FBAXTreeSerialization.describeAllElements(
      fromTree: [
        FBAXWire.Node.label.rawValue: "General Settings",
        FBAXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(CGRect(x: 10, y: 20, width: 100, height: 50)) as NSDictionary,
        FBAXWire.Node.children.rawValue: [[String: Any]](),
      ],
      keys: FBAXKeys.defaultSet, nestedFormat: false, pid: 1
    )
    let centre = FBAXTreeSerialization.frameCenter(inElements: elements, markerValue: "General", key: .label)
    XCTAssertEqual(centre?.x, 60)
    XCTAssertEqual(centre?.y, 45)
  }

  // MARK: - A marker matches by its searched key regardless of the requested key set

  // A marker is matched over the *serialized* element, so the searched key's field has to be among the
  // keys a tree was serialized with. Every marker call site therefore unions the searched key's
  // serialization key into the read set — a mapping that is only sound because each searchable key
  // serializes into the field named by its own raw value.
  func testSearchableKeyMapsToItsOwnSerializedField() {
    let searchable: [FBAXSearchableKey] = [.label, .uniqueID, .value, .title, .role, .roleDescription, .subrole, .help, .placeholder]
    for key in searchable {
      XCTAssertEqual(key.serializationKey.rawValue, key.rawValue, "\(key) must serialize into the field its marker match reads")
    }
  }

  func testMarkerMatchesWhenSearchedKeyIsOutsideTheRequestedKeySet() {
    // describe serialized with the caller's requested keys and the marker verbs with the default set,
    // so a searched key outside that set — a restricted key request, or `.placeholder`, which the
    // default set omits — was silently unmatchable even when a matching element was present.
    let tree: [String: Any] = [
      FBAXWire.Node.label.rawValue: "General Settings",
      FBAXWire.Node.children.rawValue: [[String: Any]](),
    ]
    let requested: Set<FBAXKeys> = [.value]
    let withoutSearchedKey = FBAXTreeSerialization.describeAllElements(fromTree: tree, keys: requested, nestedFormat: false, pid: 1)
    XCTAssertNil(
      FBAXTreeSerialization.matchingElement(inElements: withoutSearchedKey, markerValue: "General", key: .label),
      "a key absent from the serialized set must not resolve a marker"
    )
    let withSearchedKey = FBAXTreeSerialization.describeAllElements(
      fromTree: tree, keys: requested.union([FBAXSearchableKey.label.serializationKey]), nestedFormat: false, pid: 1
    )
    guard case let .object(fields)? = FBAXTreeSerialization.matchingElement(inElements: withSearchedKey, markerValue: "General", key: .label),
      case let .string(label)? = fields[FBAXSearchableKey.label.rawValue]
    else {
      return XCTFail("unioning the searched key must make the marker resolve regardless of the requested keys")
    }
    XCTAssertEqual(label, "General Settings")
  }

  // MARK: - FBAXTreeRead system-wide hit-test parsing

  func testHitTestParsesHitNodeAndOwningPid() throws {
    // A system-wide hit-test resolves which app owns the point, so the response carries the owning pid
    // the host tags the element with.
    let node: [String: Any] = [FBAXWire.Node.identifier.rawValue: "com.apple.settings.general"]
    let data = try envelope(["ok": true, "tree": node, "pid": 8865])
    let parsed = try FBAXTreeRead(hitTestResponse: data)
    XCTAssertEqual(parsed?.tree[FBAXWire.Node.identifier.rawValue] as? String, "com.apple.settings.general")
    XCTAssertEqual(parsed?.pid, 8865)
  }

  func testHitTestReturnsNilForEmptyResult() throws {
    // `{ok:true, empty:true}` is "no element at the point" — a valid empty result, returned as nil,
    // not conflated with a reader failure.
    let data = try envelope(["ok": true, "empty": true])
    XCTAssertNil(try FBAXTreeRead(hitTestResponse: data))
  }

  func testHitTestThrowsOnFailure() throws {
    // A failure (`ok:false`) is distinct from an empty result and is surfaced with the guest message.
    let data = try envelope(["ok": false, "error": "AXUIElementCopyElementAtPosition unavailable"])
    XCTAssertThrowsError(try FBAXTreeRead(hitTestResponse: data)) { error in
      XCTAssertTrue("\(error)".contains("AXUIElementCopyElementAtPosition unavailable"), "unexpected error: \(error)")
    }
  }

  func testHitTestThrowsWhenOkButNoTreeOrEmpty() throws {
    let data = try envelope(["ok": true])
    XCTAssertThrowsError(try FBAXTreeRead(hitTestResponse: data))
  }

  func testHitTestThrowsWhenOwningPidMissing() throws {
    // A hit node with no owning pid is a protocol violation — the host cannot tag the element.
    let data = try envelope(["ok": true, "tree": [FBAXWire.Node.identifier.rawValue: "x"]])
    XCTAssertThrowsError(try FBAXTreeRead(hitTestResponse: data)) { error in
      guard case FBAXBridgeError.guestFailure = error else {
        return XCTFail("a hit-test without an owning pid should be guestFailure, got: \(error)")
      }
    }
  }

  // MARK: - FBAXTreeRead fused frontmost tree parsing

  func testFrontmostTreeParsesTreeAndResolvedPid() throws {
    // The fused read resolves the frontmost app AND reads its tree in one call, so the response carries
    // the resolved pid the host tags elements with — it did not know the pid in advance.
    let tree: [String: Any] = [FBAXWire.Node.label.rawValue: "Settings"]
    let data = try envelope(["ok": true, "tree": tree, "pid": 8865, "method": "center-point", "truncated": false])
    let parsed = try FBAXTreeRead(frontmostResponse: data)
    XCTAssertEqual(parsed.pid, 8865)
    XCTAssertEqual(parsed.tree[FBAXWire.Node.label.rawValue] as? String, "Settings")
    XCTAssertFalse(parsed.truncated)
  }

  func testFrontmostTreeSurfacesTruncation() throws {
    let data = try envelope(["ok": true, "tree": [FBAXWire.Node.label.rawValue: "root"], "pid": 1, "truncated": true])
    XCTAssertTrue(try FBAXTreeRead(frontmostResponse: data).truncated)
  }

  func testFrontmostTreeThrowsFrontmostUnavailableOnFailure() throws {
    // A fused read that couldn't resolve/read the frontmost app maps to frontmostUnavailable, which the
    // read poll retries.
    let data = try envelope(["ok": false, "error": "system-wide hit-test at (201.0, 437.0) found no element"])
    XCTAssertThrowsError(try FBAXTreeRead(frontmostResponse: data)) { error in
      guard case FBAXBridgeError.frontmostUnavailable = error else {
        return XCTFail("a failed fused read should be frontmostUnavailable, got: \(error)")
      }
    }
  }

  func testFrontmostTreeThrowsWhenResolvedPidMissing() throws {
    // An ok response with a tree but no pid is a protocol violation — the host cannot tag the elements.
    let data = try envelope(["ok": true, "tree": [FBAXWire.Node.label.rawValue: "x"]])
    XCTAssertThrowsError(try FBAXTreeRead(frontmostResponse: data)) { error in
      guard case FBAXBridgeError.guestFailure = error else {
        return XCTFail("a fused response without a pid should be guestFailure, got: \(error)")
      }
    }
  }

  func testFrontmostTreeThrowsWhenTreeMissing() throws {
    let data = try envelope(["ok": true, "pid": 8865])
    XCTAssertThrowsError(try FBAXTreeRead(frontmostResponse: data)) { error in
      guard case FBAXBridgeError.guestFailure = error else {
        return XCTFail("a fused response without a tree should be guestFailure, got: \(error)")
      }
    }
  }

  // MARK: - Fullscreen-modal descriptor parsing + non-serialization

  func testModalParsesSystemAlert() {
    let response: [String: Any] = ["ok": true, "modal": ["kind": "system", "elementType": "SBAlertItemWindow", "label": "Allow \u{201c}Maps\u{201d} to use your location?"]]
    let modal = FBAXTreeRead.modal(fromResponse: response)
    XCTAssertEqual(modal?.kind, .system)
    XCTAssertEqual(modal?.elementType, "SBAlertItemWindow")
    XCTAssertEqual(modal?.label, "Allow \u{201c}Maps\u{201d} to use your location?")
  }

  func testModalParsesAppAlertWithoutLabel() {
    let response: [String: Any] = ["ok": true, "modal": ["kind": "app", "elementType": "_UIAlertControllerView"]]
    let modal = FBAXTreeRead.modal(fromResponse: response)
    XCTAssertEqual(modal?.kind, .app)
    XCTAssertEqual(modal?.elementType, "_UIAlertControllerView")
    XCTAssertNil(modal?.label)
  }

  func testModalAbsentOrMalformedIsNil() {
    XCTAssertNil(FBAXTreeRead.modal(fromResponse: ["ok": true]), "no modal key -> nil")
    XCTAssertNil(FBAXTreeRead.modal(fromResponse: ["ok": true, "modal": ["elementType": "X"]]), "missing kind -> nil")
    XCTAssertNil(FBAXTreeRead.modal(fromResponse: ["ok": true, "modal": ["kind": "bogus", "elementType": "X"]]), "unknown kind -> nil")
  }

  func testFrontmostTreeCarriesModalDescriptor() throws {
    let tree: [String: Any] = [FBAXWire.Node.label.rawValue: "root"]
    let data = try envelope(["ok": true, "tree": tree, "pid": 20475, "modal": ["kind": "system", "elementType": "SBAlertItemWindow", "label": "Allow"]])
    let parsed = try FBAXTreeRead(frontmostResponse: data)
    XCTAssertEqual(parsed.pid, 20475)
    XCTAssertEqual(parsed.modal?.kind, .system)
    XCTAssertEqual(parsed.modal?.elementType, "SBAlertItemWindow")
  }

  func testModalIsNeverSerializedInTheCLIOutput() throws {
    // The modal field enriches the host view but MUST NOT change the emitted CLI/gRPC JSON — a response
    // with a modal must serialize byte-identically to one without.
    let modal = FBAccessibilityModalInfo(kind: .system, elementType: "SBAlertItemWindow", label: "Allow")
    let withModal = FBAccessibilityElementsResponse(elements: .array([]), modal: modal)
    let without = FBAccessibilityElementsResponse(elements: .array([]))
    let a = try JSONSerialization.data(withJSONObject: withModal.asDictionary(), options: .sortedKeys)
    let b = try JSONSerialization.data(withJSONObject: without.asDictionary(), options: .sortedKeys)
    XCTAssertEqual(a, b, "the modal descriptor must not appear in the serialized output")
  }

  // MARK: - Tree -> shared serializer integration

  func testGuestTreeFeedsSharedSerializerSchema() throws {
    // A guest envelope carrying a small XC_kAXXC* tree round-trips through the same path the
    // testmanagerd backend uses (`FBAXTreeRead(wholeTreeResponse:)` -> `describeAllElements`), producing the
    // shared schema: the child is a Button (automationType 9) with its identifier, proving the
    // axbridge output is byte-compatible with the shared serializer rather than a bespoke shape.
    let tree: [String: Any] = [
      FBAXWire.Node.label.rawValue: "root",
      FBAXWire.Node.children.rawValue: [
        [
          FBAXWire.Node.label.rawValue: "General",
          FBAXWire.Node.identifier.rawValue: "com.apple.settings.general",
          FBAXWire.Node.automationType.rawValue: 9,
          FBAXWire.Node.children.rawValue: [[String: Any]](),
        ] as [String: Any]
      ],
    ]
    let data = try envelope(["ok": true, "tree": tree])
    let parsed = try FBAXTreeRead(wholeTreeResponse: data, pid: 99)

    let elements = FBAXTreeSerialization.describeAllElements(
      fromTree: parsed.tree, keys: FBAXKeys.defaultSet, nestedFormat: false, pid: 99
    )
    XCTAssertEqual(elements.count, 2, "expected the root plus its one child, flattened")

    let response = FBAccessibilityElementsResponse(
      elements: .array(elements)
    )
    let json = try JSONSerialization.data(withJSONObject: response.asDictionary(), options: .sortedKeys)
    let serialized = String(data: json, encoding: .utf8) ?? ""
    XCTAssertTrue(serialized.contains("com.apple.settings.general"), "missing identifier in \(serialized)")
    // automationType 9 maps to the readable XCUIElementType name via the shared serializer.
    XCTAssertTrue(serialized.contains("\"role\":\"Button\""), "role not mapped in \(serialized)")
  }
}

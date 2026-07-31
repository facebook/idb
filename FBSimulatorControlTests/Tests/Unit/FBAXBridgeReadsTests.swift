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
/// envelope parsing (`FBAXBridgeResponse`) and the tree -> shared-serializer integration that makes
/// the axbridge output identical to the testmanagerd backend (both feed `describeAllElements`).
final class FBAXBridgeReadsTests: XCTestCase {

  private func envelope(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
  }

  // MARK: - FBAXBridgeResponse envelope parsing

  func testParsesTreeFromOkEnvelope() throws {
    let tree: [String: Any] = [
      FBRemoteAutomationAXAttribute.label: "General",
      FBRemoteAutomationAXAttribute.identifier: "com.apple.settings.general",
    ]
    let data = try envelope(["ok": true, "tree": tree])
    let parsed = try FBAXBridgeResponse.tree(fromResponse: data, pid: 42)
    XCTAssertEqual(parsed[FBRemoteAutomationAXAttribute.label] as? String, "General")
    XCTAssertEqual(parsed[FBRemoteAutomationAXAttribute.identifier] as? String, "com.apple.settings.general")
  }

  func testSurfacesGuestErrorMessage() throws {
    // An untagged failure (no `error_kind`) is an opaque `guestFailure` carrying the guest's own
    // message, so callers see the real cause.
    let data = try envelope(["ok": false, "error": "the accessibility server is not responding"])
    XCTAssertThrowsError(try FBAXBridgeResponse.tree(fromResponse: data, pid: 7)) { error in
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
    XCTAssertThrowsError(try FBAXBridgeResponse.tree(fromResponse: data, pid: 7)) { error in
      guard case let FBAXBridgeError.applicationUnavailable(pid) = error else {
        return XCTFail("a tagged failure should be applicationUnavailable, got: \(error)")
      }
      XCTAssertEqual(pid, 7)
    }
  }

  func testThrowsOnMalformedResponse() {
    let data = Data("this is not json".utf8)
    XCTAssertThrowsError(try FBAXBridgeResponse.tree(fromResponse: data, pid: 1))
  }

  func testThrowsWhenOkButNoTree() throws {
    let data = try envelope(["ok": true])
    XCTAssertThrowsError(try FBAXBridgeResponse.tree(fromResponse: data, pid: 1))
  }

  func testThrowsWhenNotOk() throws {
    // `ok` missing/false with no `error` still fails rather than yielding an empty tree.
    let data = try envelope(["tree": [FBRemoteAutomationAXAttribute.label: "x"]])
    XCTAssertThrowsError(try FBAXBridgeResponse.tree(fromResponse: data, pid: 1))
  }

  // MARK: - One error type across backends

  // The point of the unified error: a caller holding `any FBUIAutomation` does not statically know
  // its backend, so "not found" has to be catchable without knowing. One catch clause must handle
  // every backend, and the message must still say which one spoke.
  func testOneCatchClauseHandlesEveryBackend() {
    let backends: [FBUIAutomationBackend] = [.accessibility, .remoteAutomation, .axBridge, .axBridgePersistent]
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
    let error = FBUIAutomationError.noElementAtPoint(backend: .axBridge, x: 2000, y: 2000)
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
        FBRemoteAutomationAXAttribute.label: "root",
        FBRemoteAutomationAXAttribute.children: [
          [FBRemoteAutomationAXAttribute.label: "General Settings", FBRemoteAutomationAXAttribute.children: [[String: Any]]()] as [String: Any]
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
        FBRemoteAutomationAXAttribute.label: "General Settings",
        FBRemoteAutomationAXAttribute.frame: CGRectCreateDictionaryRepresentation(CGRect(x: 10, y: 20, width: 100, height: 50)) as NSDictionary,
        FBRemoteAutomationAXAttribute.children: [[String: Any]](),
      ],
      keys: FBAXKeys.defaultSet, nestedFormat: false, pid: 1
    )
    let centre = FBAXTreeSerialization.frameCenter(inElements: elements, markerValue: "General", key: .label)
    XCTAssertEqual(centre?.x, 60)
    XCTAssertEqual(centre?.y, 45)
  }

  // MARK: - FBAXBridgeResponse hit-test parsing

  func testHitTestParsesHitNode() throws {
    let node: [String: Any] = [FBRemoteAutomationAXAttribute.identifier: "com.apple.settings.general"]
    let data = try envelope(["ok": true, "tree": node])
    let parsed = try FBAXBridgeResponse.hitTest(fromResponse: data, pid: 42)
    XCTAssertEqual(parsed?[FBRemoteAutomationAXAttribute.identifier] as? String, "com.apple.settings.general")
  }

  func testHitTestReturnsNilForEmptyResult() throws {
    // `{ok:true, empty:true}` is "no element at the point" — a valid empty result, returned as nil,
    // not conflated with a reader failure.
    let data = try envelope(["ok": true, "empty": true])
    XCTAssertNil(try FBAXBridgeResponse.hitTest(fromResponse: data, pid: 42))
  }

  func testHitTestThrowsOnFailure() throws {
    // A failure (`ok:false`) is distinct from an empty result and is surfaced with the guest message.
    let data = try envelope(["ok": false, "error": "AXUIElementCopyElementAtPosition unavailable"])
    XCTAssertThrowsError(try FBAXBridgeResponse.hitTest(fromResponse: data, pid: 42)) { error in
      XCTAssertTrue("\(error)".contains("AXUIElementCopyElementAtPosition unavailable"), "unexpected error: \(error)")
    }
  }

  func testHitTestThrowsWhenOkButNoTreeOrEmpty() throws {
    let data = try envelope(["ok": true])
    XCTAssertThrowsError(try FBAXBridgeResponse.hitTest(fromResponse: data, pid: 1))
  }

  // MARK: - Tree -> shared serializer integration

  func testGuestTreeFeedsSharedSerializerSchema() throws {
    // A guest envelope carrying a small XC_kAXXC* tree round-trips through the same path the
    // testmanagerd backend uses (`FBAXBridgeResponse.tree` -> `describeAllElements`), producing the
    // shared schema: the child is a Button (automationType 9) with its identifier, proving the
    // axbridge output is byte-compatible with the shared serializer rather than a bespoke shape.
    let tree: [String: Any] = [
      FBRemoteAutomationAXAttribute.label: "root",
      FBRemoteAutomationAXAttribute.children: [
        [
          FBRemoteAutomationAXAttribute.label: "General",
          FBRemoteAutomationAXAttribute.identifier: "com.apple.settings.general",
          FBRemoteAutomationAXAttribute.automationType: 9,
          FBRemoteAutomationAXAttribute.children: [[String: Any]](),
        ] as [String: Any]
      ],
    ]
    let data = try envelope(["ok": true, "tree": tree])
    let parsed = try FBAXBridgeResponse.tree(fromResponse: data, pid: 99)

    let elements = FBAXTreeSerialization.describeAllElements(
      fromTree: parsed, keys: FBAXKeys.defaultSet, nestedFormat: false, pid: 99
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

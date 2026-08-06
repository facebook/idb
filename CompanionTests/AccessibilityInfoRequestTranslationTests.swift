/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
@preconcurrency import FBControlCore
import FBSimulatorControl
import GRPC
import IDBGRPCSwift
import XCTest

/// Pins the `accessibility_info` request → framework translation and the legacy output byte shape.
/// This is the wire contract the gRPC surface has always served; later changes (backend selection,
/// the `complete` format) must leave every pin here untouched.
final class AccessibilityInfoRequestTranslationTests: XCTestCase {

  // MARK: - Format mapping

  func testOutputFormatMapsLegacyAndNested() {
    XCTAssertEqual(AccessibilityInfoRequestTranslation.outputFormat(from: .legacy), .default)
    XCTAssertEqual(AccessibilityInfoRequestTranslation.outputFormat(from: .nested), .nested)
  }

  func testUnrecognizedFormatFallsBackToLegacy() {
    XCTAssertEqual(
      AccessibilityInfoRequestTranslation.outputFormat(from: .UNRECOGNIZED(99)), .default,
      "an unknown format from a newer client degrades to the historical output rather than failing the call"
    )
  }

  // MARK: - Searchable-key mapping

  func testSearchableKeyMapsEveryWireValue() {
    let expected: [(Idb_AccessibilityActionRequest.SearchableKey, FBAXSearchableKey)] = [
      (.label, .label), (.uniqueID, .uniqueID), (.value, .value), (.title, .title),
      (.role, .role), (.roleDescription, .roleDescription), (.subrole, .subrole),
      (.help, .help), (.placeholder, .placeholder),
    ]
    XCTAssertEqual(
      expected.count, Idb_AccessibilityActionRequest.SearchableKey.allCases.count,
      "a searchable key added to the proto must be added to this map"
    )
    for (wire, key) in expected {
      XCTAssertEqual(AccessibilityInfoRequestTranslation.searchableKey(from: wire), key)
    }
  }

  func testUnrecognizedSearchableKeyFallsBackToLabel() {
    XCTAssertEqual(AccessibilityInfoRequestTranslation.searchableKey(from: .UNRECOGNIZED(42)), .label)
  }

  // MARK: - Query construction

  func testEmptyMarkerIsNotAMarkerQuery() {
    XCTAssertNil(AccessibilityInfoRequestTranslation.markerQuery(from: .init()))
  }

  func testMarkerQueryCarriesValueKeyAndDepth() {
    var request = Idb_AccessibilityInfoRequest()
    request.marker = "Settings"
    request.matchKey = .uniqueID
    request.depth = 7
    XCTAssertEqual(
      AccessibilityInfoRequestTranslation.markerQuery(from: request),
      .marker(value: "Settings", key: .uniqueID, depth: 7)
    )
  }

  // MARK: - Point

  func testNoPointMeansFrontmost() {
    XCTAssertNil(AccessibilityInfoRequestTranslation.point(from: .init()))
  }

  func testPointRoundTrips() throws {
    var request = Idb_AccessibilityInfoRequest()
    request.point = .with {
      $0.x = 12
      $0.y = 34
    }
    let value = try XCTUnwrap(AccessibilityInfoRequestTranslation.point(from: request))
    XCTAssertEqual(value.pointValue, NSPoint(x: 12, y: 34))
  }

  // MARK: - Keys

  func testEmptyKeysSelectTheDefaultSet() throws {
    let options = try AccessibilityInfoRequestTranslation.options(from: .init(), format: .default)
    XCTAssertEqual(options.keys, FBAXKeys.defaultSet)
  }

  func testUnrecognizedKeysInAPartiallyValidListAreDropped() throws {
    var request = Idb_AccessibilityInfoRequest()
    request.keys = ["AXLabel", "not-a-key"]
    let options = try AccessibilityInfoRequestTranslation.options(from: request, format: .default)
    let label = try XCTUnwrap(FBAXKeys(rawValue: "AXLabel"))
    XCTAssertEqual(
      options.keys, Set([label]),
      "deliberately lenient: invalid keys drop silently as long as one key is recognized"
    )
  }

  func testAllInvalidKeysAreRejected() {
    var request = Idb_AccessibilityInfoRequest()
    request.keys = ["not-a-key", "also-not-a-key"]
    XCTAssertThrowsError(try AccessibilityInfoRequestTranslation.options(from: request, format: .default)) { error in
      guard let status = error as? GRPCStatus else {
        return XCTFail("expected GRPCStatus, got \(error)")
      }
      XCTAssertEqual(status.code, .invalidArgument)
    }
  }

  func testOptionsPinTheHandlerDefaults() throws {
    let options = try AccessibilityInfoRequestTranslation.options(from: .init(), format: .nested)
    XCTAssertEqual(options.format, .nested)
    XCTAssertTrue(options.enableLogging)
    XCTAssertFalse(options.enableProfiling)
    XCTAssertFalse(options.collectFrameCoverage)
  }

  // MARK: - Backend selection

  func testUnspecifiedBackendPreservesTheHistoricalPath() {
    XCTAssertEqual(AccessibilityInfoRequestTranslation.backend(from: .unspecified), .accessibility)
  }

  func testBackendMapsThroughTheSharedVocabulary() {
    XCTAssertEqual(AccessibilityInfoRequestTranslation.backend(from: .ax), .accessibility)
    XCTAssertEqual(
      AccessibilityInfoRequestTranslation.backend(from: .axbridge),
      .axBridge(persistence: .oneShot, frontmostMethod: .centerPoint)
    )
    XCTAssertEqual(
      AccessibilityInfoRequestTranslation.backend(from: .axbridgePersistent),
      .axBridge(persistence: .persistent, frontmostMethod: .centerPoint),
      "the persistent transport is selected for a long-lived server, which amortizes its warm reads"
    )
  }

  func testUnrecognizedBackendPreservesTheHistoricalPath() {
    XCTAssertEqual(AccessibilityInfoRequestTranslation.backend(from: .UNRECOGNIZED(9)), .accessibility)
  }

  // MARK: - Legacy output shape

  func testTreeSerializesAsABareArray() throws {
    let response = FBAccessibilityElementsResponse(elements: .tree([FBAccessibilityDocumentElement()]))
    let data = try AccessibilityInfoRequestTranslation.legacyJSON(from: response)
    XCTAssertEqual(
      String(data: data, encoding: .utf8), "[{}]",
      "point/frontmost reads emit the bare element array — not the {\"elements\":…} envelope the marker path uses"
    )
  }

  func testSingleSerializesAsABareObject() throws {
    let response = FBAccessibilityElementsResponse(elements: .single(FBAccessibilityDocumentElement()))
    let data = try AccessibilityInfoRequestTranslation.legacyJSON(from: response)
    XCTAssertEqual(String(data: data, encoding: .utf8), "{}")
  }
}

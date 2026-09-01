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

/// Records the options the handler hands the command executor, so a test can read them without a
/// simulator. `FBIDBCommandExecutor` is a `public final class`; `AccessibilityDescribing` is the seam
/// the handler is written against, and this double stands in for it.
private final class RecordingAccessibilityExecutor: AccessibilityDescribing {
  private(set) var describeOptions: FBAccessibilityRequestOptions?
  private(set) var describeQuery: FBAccessibilityElementQuery?
  private(set) var pointReadCount = 0

  func accessibility_describe(
    query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions,
    backend: FBUIAutomationBackend
  ) async throws -> Data {
    describeQuery = query
    describeOptions = options
    return Data("{}".utf8)
  }

  func accessibility_info_at_point(
    _ value: NSValue?,
    options: FBAccessibilityRequestOptions,
    backend: FBUIAutomationBackend
  ) async throws -> FBAccessibilityElementsResponse {
    pointReadCount += 1
    return FBAccessibilityElementsResponse(elements: .single(FBAccessibilityDocumentElement()))
  }
}

/// Guards the bug this diff fixes at the layer it lived in. A describe-by-marker used to reach the
/// executor with a format-only options set — the request's `--key`/`--profile`/`--collect-frame-coverage`
/// were dropped between the wire and the reader. `AccessibilityInfoRequestTranslation.options(from:)`
/// already carried them for the at-point path (added earlier in this stack), so a test on that
/// translation passes before the fix and does not guard it; the regression is only visible in what
/// the *handler* hands the executor on the marker path, which is what these tests assert.
final class AccessibilityInfoMethodHandlerTests: XCTestCase {

  func testMarkerReadCarriesTheRequestedKeysToTheExecutor() async throws {
    let executor = RecordingAccessibilityExecutor()
    var request = Idb_AccessibilityInfoRequest()
    request.marker = "OK"
    request.keys = ["AXLabel"]

    _ = try await AccessibilityInfoMethodHandler.respond(to: request, using: executor)

    let options = try XCTUnwrap(
      executor.describeOptions, "a marker read must reach the describe executor, not the at-point path")
    let label = try XCTUnwrap(FBAXKeys(rawValue: "AXLabel"))
    XCTAssertEqual(
      options.keys, Set([label]),
      "the request's --key must reach the executor on the marker path, not a format-only default set")
    XCTAssertEqual(executor.pointReadCount, 0, "a marker read must not fall through to the at-point read")
  }

  func testMarkerReadCarriesProfilingAndFrameCoverageToTheExecutor() async throws {
    let executor = RecordingAccessibilityExecutor()
    var request = Idb_AccessibilityInfoRequest()
    request.marker = "OK"
    request.profile = true
    request.collectFrameCoverage = true

    _ = try await AccessibilityInfoMethodHandler.respond(to: request, using: executor)

    let options = try XCTUnwrap(executor.describeOptions)
    XCTAssertTrue(options.enableProfiling, "--profile is a read option and a marker read is a read")
    XCTAssertTrue(
      options.collectFrameCoverage, "--collect-frame-coverage is a read option and a marker read is a read")
  }
}

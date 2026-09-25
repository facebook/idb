/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class UIAutomationPollingTests: XCTestCase {
  func testMatchOnTheDeadlineWinsOverTimeout() async throws {
    var now = 0.0
    let result: AccessibilitySearchResult<String> = try await UIAutomationPolling.pollUntilFound(
      timeout: 1, pollInterval: 0.5, clock: { now }, sleep: { now += $0 }
    ) {
      AccessibilitySearchResult(match: now == 1 ? "ready" : nil)
    }
    XCTAssertEqual(result.match, "ready")
    XCTAssertEqual(now, 1)
  }

  func testZeroTimeoutStillProbesOnce() async throws {
    var probes = 0
    let result: AccessibilitySearchResult<String> = try await UIAutomationPolling.pollUntilFound(
      timeout: 0, pollInterval: 0.5, clock: { 0 },
      sleep: { _ in XCTFail("an expired wait must not sleep") }
    ) {
      probes += 1
      return AccessibilitySearchResult(match: nil, diagnostics: AccessibilitySearchDiagnostics(unmatchedValues: ["probe \(probes)"]))
    }
    XCTAssertNil(result.match)
    XCTAssertEqual(result.diagnostics?.unmatchedValues, ["probe 1"])
    XCTAssertEqual(probes, 1)
  }

  func testTimeoutDoesNotProbeAgainAfterTheFinalMiss() async throws {
    var now = 0.0
    var probes = 0
    let result: AccessibilitySearchResult<String> = try await UIAutomationPolling.pollUntilFound(
      timeout: 1, pollInterval: 0.5, clock: { now }, sleep: { now += $0 }
    ) {
      probes += 1
      return AccessibilitySearchResult(match: nil, diagnostics: AccessibilitySearchDiagnostics(unmatchedValues: ["probe \(probes)"]))
    }
    XCTAssertNil(result.match)
    XCTAssertEqual(result.diagnostics?.unmatchedValues, ["probe 3"])
    XCTAssertEqual(probes, 3)
    XCTAssertEqual(now, 1)
  }

  func testFinalReadFailureReplacesEarlierValues() async throws {
    var now = 0.0
    let result: AccessibilitySearchResult<String> = try await UIAutomationPolling.pollUntilFound(
      timeout: 1, pollInterval: 1, clock: { now }, sleep: { now += $0 }
    ) {
      AccessibilitySearchResult(
        match: nil,
        diagnostics: now == 0
          ? AccessibilitySearchDiagnostics(unmatchedValues: ["old screen"])
          : AccessibilitySearchDiagnostics(readError: "application unavailable"))
    }
    XCTAssertEqual(result.diagnostics, AccessibilitySearchDiagnostics(readError: "application unavailable"))
  }

  func testMappingAMatchPreservesNonmatches() {
    let result = AccessibilitySearchResult(match: "ready", diagnostics: AccessibilitySearchDiagnostics(unmatchedValues: ["loading"]))
    let mapped = result.map { $0.count }
    XCTAssertEqual(mapped.match, 5)
    XCTAssertEqual(mapped.diagnostics, result.diagnostics)
  }

  func testDiagnosticSampleBoundsValuesAndText() {
    let values = AccessibilitySearchDiagnostics(unmatchedValues: (0..<51).map(String.init))
    XCTAssertEqual(values.unmatchedValues, (0..<50).map(String.init))
    XCTAssertTrue(values.truncated)
    let text = AccessibilitySearchDiagnostics(unmatchedValues: [String(repeating: "x", count: 201)])
    XCTAssertEqual(text.unmatchedValues, [String(repeating: "x", count: 200)])
    XCTAssertTrue(text.truncated)
  }

  func testProbeFailureAndSleepCancellationPropagate() async throws {
    enum ReadError: Error { case failed }
    do {
      let _: AccessibilitySearchResult<String> = try await UIAutomationPolling.pollUntilFound(
        timeout: 1, pollInterval: 0.5, clock: { 0 },
        sleep: { _ in XCTFail("a failed probe must not sleep") }
      ) {
        throw ReadError.failed
      }
      XCTFail("a failed probe must throw")
    } catch {
      XCTAssertTrue(error is ReadError)
    }

    do {
      let _: AccessibilitySearchResult<String> = try await UIAutomationPolling.pollUntilFound(
        timeout: 1, pollInterval: 0.5, clock: { 0 },
        sleep: { _ in throw CancellationError() }
      ) {
        AccessibilitySearchResult(match: nil)
      }
      XCTFail("cancellation must throw")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
  }
}

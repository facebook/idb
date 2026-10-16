/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorAX
@testable import FBSimulatorControl
import Foundation
import Testing

@Suite
struct UIAutomationPollingTests {
  @Test
  func matchOnTheDeadlineWinsOverTimeout() async throws {
    var now = 0.0
    let result: AccessibilitySearchResult<String> = try await UIAutomationPolling.pollUntilFound(
      timeout: 1, pollInterval: 0.5, clock: { now }, sleep: { now += $0 }
    ) {
      AccessibilitySearchResult(match: now == 1 ? "ready" : nil)
    }
    #expect(result.match == "ready")
    #expect(now == 1)
  }

  @Test
  func zeroTimeoutStillProbesOnce() async throws {
    var probes = 0
    let result: AccessibilitySearchResult<String> = try await UIAutomationPolling.pollUntilFound(
      timeout: 0, pollInterval: 0.5, clock: { 0 },
      sleep: { _ in Issue.record("an expired wait must not sleep") }
    ) {
      probes += 1
      return AccessibilitySearchResult(match: nil, diagnostics: AccessibilitySearchDiagnostics(unmatchedValues: ["probe \(probes)"]))
    }
    #expect(result.match == nil)
    #expect(result.diagnostics?.unmatchedValues == ["probe 1"])
    #expect(probes == 1)
  }

  @Test
  func timeoutDoesNotProbeAgainAfterTheFinalMiss() async throws {
    var now = 0.0
    var probes = 0
    let result: AccessibilitySearchResult<String> = try await UIAutomationPolling.pollUntilFound(
      timeout: 1, pollInterval: 0.5, clock: { now }, sleep: { now += $0 }
    ) {
      probes += 1
      return AccessibilitySearchResult(match: nil, diagnostics: AccessibilitySearchDiagnostics(unmatchedValues: ["probe \(probes)"]))
    }
    #expect(result.match == nil)
    #expect(result.diagnostics?.unmatchedValues == ["probe 3"])
    #expect(probes == 3)
    #expect(now == 1)
  }

  @Test
  func finalReadFailureReplacesEarlierValues() async throws {
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
    #expect(result.diagnostics == AccessibilitySearchDiagnostics(readError: "application unavailable"))
  }

  @Test
  func mappingAMatchPreservesNonmatches() {
    let result = AccessibilitySearchResult(match: "ready", diagnostics: AccessibilitySearchDiagnostics(unmatchedValues: ["loading"]))
    let mapped = result.map { $0.count }
    #expect(mapped.match == 5)
    #expect(mapped.diagnostics == result.diagnostics)
  }

  @Test
  func diagnosticSampleBoundsValuesAndText() {
    let values = AccessibilitySearchDiagnostics(unmatchedValues: (0..<51).map(String.init))
    #expect(values.unmatchedValues == (0..<50).map(String.init))
    #expect(values.truncated)
    let text = AccessibilitySearchDiagnostics(unmatchedValues: [String(repeating: "x", count: 201)])
    #expect(text.unmatchedValues == [String(repeating: "x", count: 200)])
    #expect(text.truncated)
  }

  @Test
  func probeFailureAndSleepCancellationPropagate() async throws {
    enum ReadError: Error { case failed }
    do {
      let _: AccessibilitySearchResult<String> = try await UIAutomationPolling.pollUntilFound(
        timeout: 1, pollInterval: 0.5, clock: { 0 },
        sleep: { _ in Issue.record("a failed probe must not sleep") }
      ) {
        throw ReadError.failed
      }
      Issue.record("a failed probe must throw")
    } catch {
      #expect(error is ReadError)
    }

    do {
      let _: AccessibilitySearchResult<String> = try await UIAutomationPolling.pollUntilFound(
        timeout: 1, pollInterval: 0.5, clock: { 0 },
        sleep: { _ in throw CancellationError() }
      ) {
        AccessibilitySearchResult(match: nil)
      }
      Issue.record("cancellation must throw")
    } catch {
      #expect(error is CancellationError)
    }
  }
}

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
    let result: String? = try await UIAutomationPolling.pollUntilFound(
      timeout: 1, pollInterval: 0.5, clock: { now }, sleep: { now += $0 }
    ) {
      now == 1 ? "ready" : nil
    }
    XCTAssertEqual(result, "ready")
    XCTAssertEqual(now, 1)
  }

  func testZeroTimeoutStillProbesOnce() async throws {
    var probes = 0
    let result: String? = try await UIAutomationPolling.pollUntilFound(
      timeout: 0, pollInterval: 0.5, clock: { 0 },
      sleep: { _ in XCTFail("an expired wait must not sleep") }
    ) {
      probes += 1
      return nil
    }
    XCTAssertNil(result)
    XCTAssertEqual(probes, 1)
  }

  func testTimeoutDoesNotProbeAgainAfterTheFinalMiss() async throws {
    var now = 0.0
    var probes = 0
    let result: String? = try await UIAutomationPolling.pollUntilFound(
      timeout: 1, pollInterval: 0.5, clock: { now }, sleep: { now += $0 }
    ) {
      probes += 1
      return nil
    }
    XCTAssertNil(result)
    XCTAssertEqual(probes, 3)
    XCTAssertEqual(now, 1)
  }

  func testProbeFailureAndSleepCancellationPropagate() async throws {
    enum ReadError: Error { case failed }
    do {
      let _: String? = try await UIAutomationPolling.pollUntilFound(
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
      let _: String? = try await UIAutomationPolling.pollUntilFound(
        timeout: 1, pollInterval: 0.5, clock: { 0 },
        sleep: { _ in throw CancellationError() }
      ) {
        nil
      }
      XCTFail("cancellation must throw")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
  }
}

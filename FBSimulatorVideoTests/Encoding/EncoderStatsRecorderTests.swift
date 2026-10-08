/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorVideo
import XCTest

final class EncoderStatsRecorderTests: XCTestCase {
  func testTheFirstCallbackReportsHowLongAfterItsFrameWasSubmitted() throws {
    let logger = CapturingLogger()
    let recorder = EncoderStatsRecorder(logger: logger)
    recorder.recordSubmissionStarting(at: .now - .milliseconds(5))
    recorder.record(.written(encodedBytes: 1))
    recorder.recordEncodeSubmission(.milliseconds(5))
    recorder.record(.written(encodedBytes: 1))
    let lines = logger.messages.compactMap { $0 as? String }.filter { $0.hasPrefix("First encode callback received") }
    XCTAssertEqual(lines.count, 1)
    let line = try XCTUnwrap(lines.first)
    XCTAssertTrue(line.hasSuffix(" ms after its frame was submitted"), line)
    let milliseconds = try XCTUnwrap(Double(line.split(separator: " ")[4]))
    XCTAssertGreaterThanOrEqual(milliseconds, 5)
  }

  func testAFirstCallbackWithoutASubmissionReportsNoLatency() {
    let logger = CapturingLogger()
    let recorder = EncoderStatsRecorder(logger: logger)
    recorder.record(.dropped)
    XCTAssertEqual(logger.messages.compactMap { $0 as? String }, ["First encode callback received"])
  }
}

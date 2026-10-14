/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorVideo
import Foundation
import Testing

@Suite
struct EncoderStatsRecorderTests {
  @Test
  func theFirstCallbackReportsHowLongAfterItsFrameWasSubmitted() throws {
    let logger = CapturingLogger()
    let recorder = EncoderStatsRecorder(logger: logger)
    recorder.recordSubmissionStarting(at: .now - .milliseconds(5))
    recorder.record(.written(encodedBytes: 1))
    recorder.recordEncodeSubmission(.milliseconds(5))
    recorder.record(.written(encodedBytes: 1))
    let lines = logger.messages.compactMap { $0 as? String }.filter { $0.hasPrefix("First encode callback received") }
    #expect(lines.count == 1)
    let line = try #require(lines.first)
    #expect(line.hasSuffix(" ms after its frame was submitted"), "\(line)")
    let milliseconds = try #require(Double(line.split(separator: " ")[4]))
    #expect(milliseconds >= 5)
  }

  @Test
  func aFirstCallbackWithoutASubmissionReportsNoLatency() {
    let logger = CapturingLogger()
    let recorder = EncoderStatsRecorder(logger: logger)
    recorder.record(.dropped)
    #expect(logger.messages.compactMap { $0 as? String } == ["First encode callback received"])
  }
}

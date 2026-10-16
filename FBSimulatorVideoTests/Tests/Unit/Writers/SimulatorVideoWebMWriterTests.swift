/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import FBControlCore
@testable import FBSimulatorControl
@testable import FBSimulatorVideo
import XCTest

final class SimulatorVideoWebMWriterTests: XCTestCase {

  private func makePath() -> String {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("SimulatorVideoWebMWriterTests-\(UUID().uuidString).webm")
    addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
    return path
  }

  private func sample(at seconds: Int64) -> CMSampleBuffer {
    var timing = CMSampleTimingInfo(duration: CMTimeMake(value: 1, timescale: 30), presentationTimeStamp: CMTimeMake(value: seconds, timescale: 1), decodeTimeStamp: .invalid)
    var copy: CMSampleBuffer?
    let status = CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: createH264SampleBuffer(), sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy)
    precondition(status == noErr, "Failed to copy sample buffer timing: \(status)")
    return copy!
  }

  func testWritesTheRecordingsFramesAndChapters() async throws {
    let path = makePath()
    let logger = CapturingLogger()
    let writer = SimulatorVideoWebMWriter(filePath: path, chaptersEnabled: true, logger: logger)
    XCTAssertTrue(writer.carriesFrameSizeChanges)
    XCTAssertNil(writer.startPresentationTime)

    writer.writeTimedMetadata("before the first frame", logger: logger)
    XCTAssertTrue(writer.consume(sample(at: 10), logger: logger))
    XCTAssertTrue(writer.consume(sample(at: 11), logger: logger))
    writer.writeTimedMetadata("second", logger: logger)
    XCTAssertTrue(writer.consume(sample(at: 12), logger: logger))
    try await writer.finish()

    XCTAssertEqual(writer.startPresentationTime, CMTimeMake(value: 10, timescale: 1))
    let recording = try WebMTestReader(path: path)
    XCTAssertEqual(recording.docType, "webm")
    XCTAssertEqual(recording.blocks.count, 3)
    XCTAssertEqual(recording.chapterTitles, ["before the first frame", "second"])
  }

  func testChaptersAreLeftOutWhenNotEnabled() async throws {
    let path = makePath()
    let logger = CapturingLogger()
    let writer = SimulatorVideoWebMWriter(filePath: path, logger: logger)
    XCTAssertTrue(writer.consume(sample(at: 0), logger: logger))
    writer.writeTimedMetadata("dropped", logger: logger)
    try await writer.finish()

    XCTAssertEqual(try WebMTestReader(path: path).chapterTitles, [])
  }

  func testFinishWithoutFramesWritesNothing() async throws {
    let path = makePath()
    try await SimulatorVideoWebMWriter(filePath: path, logger: CapturingLogger()).finish()
    XCTAssertFalse(FileManager.default.fileExists(atPath: path))
  }
}

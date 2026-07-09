/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBProcessStreamTests: XCTestCase {

  func testClosingActiveStreamStopsWriting() throws {
    let consumer = FBDataBuffer.consumableBuffer()

    let output = FBProcessOutput<FBDataConsumer>(for: consumer)
    let attachment: FBProcessStreamAttachment = try output.attach().`await`()
    XCTAssertTrue(attachment.fileDescriptor != 0)
    XCTAssertEqual(attachment.mode, FBProcessStreamAttachmentMode.output)

    var data = "HELLO WORLD\n".data(using: .utf8)!
    data.withUnsafeBytes { buffer in
      Darwin.write(attachment.fileDescriptor, buffer.baseAddress!, buffer.count)
    }
    data = "HELLO AGAIN".data(using: .utf8)!
    data.withUnsafeBytes { buffer in
      Darwin.write(attachment.fileDescriptor, buffer.baseAddress!, buffer.count)
    }

    try output.detach().`await`()

    XCTAssertTrue(consumer.finishedConsuming.hasCompleted)
  }

  func testViaFifo() throws {
    let buffer = FBDataBuffer.accumulatingBuffer()
    let output = FBProcessOutput<FBDataConsumer>(for: buffer)
    let fileOutput: FBProcessFileOutput = try output.providedThroughFile().`await`()
    XCTAssertNotNil(fileOutput)

    let startReading = fileOutput.startReading()
    let fileHandle = FileHandle(forWritingAtPath: fileOutput.filePath)
    try startReading.`await`()

    fileHandle!.write("HELLO WORLD\n".data(using: .utf8)!)
    fileHandle!.write("HELLO AGAIN".data(using: .utf8)!)
    fileHandle!.closeFile()

    try buffer.finishedConsuming.`await`()

    let expected: [String] = ["HELLO WORLD", "HELLO AGAIN"]
    XCTAssertEqual(buffer.lines() as! [String], expected)
  }

  func testFileToFileDoesNotInvolveIndirection() throws {
    let filePath = "/tmp/hello_world.txt"
    let output = FBProcessOutput<NSString>(forFilePath: filePath)
    let fileOutput: FBProcessFileOutput = try output.providedThroughFile().`await`()
    XCTAssertNotNil(fileOutput)

    XCTAssertEqual(filePath, fileOutput.filePath)
  }

  func testConcurrentAttachmentIsProhibited() throws {
    let consumer = FBDataBuffer.consumableBuffer()
    let output = FBProcessOutput<FBDataConsumer>(for: consumer)

    let concurrentQueue = DispatchQueue.global(qos: .userInitiated)
    let group = DispatchGroup()
    var firstAttempt: FBFuture<FBProcessStreamAttachment>!
    var secondAttempt: FBFuture<FBProcessStreamAttachment>!
    var thirdAttempt: FBFuture<FBProcessStreamAttachment>!

    group.enter()
    concurrentQueue.async {
      firstAttempt = output.attach()
      group.leave()
    }
    group.enter()
    concurrentQueue.async {
      secondAttempt = output.attach()
      group.leave()
    }
    group.enter()
    concurrentQueue.async {
      thirdAttempt = output.attach()
      group.leave()
    }
    group.wait()

    try? firstAttempt.`await`()
    try? secondAttempt.`await`()
    try? thirdAttempt.`await`()

    var successes: UInt = 0
    if firstAttempt.state == FBFutureState.done {
      successes += 1
    }
    if secondAttempt.state == FBFutureState.done {
      successes += 1
    }
    if thirdAttempt.state == FBFutureState.done {
      successes += 1
    }

    try output.detach().`await`()
    XCTAssertEqual(successes, 1)
  }
}

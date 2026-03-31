/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import FBControlCore

final class FBControlCoreLoggerTests: XCTestCase {
  func testLoggingToFileDescriptor() {
    let filename = "\(UUID().uuidString).log"
    let temporaryFilePath = NSTemporaryDirectory().appending(filename)
    FileManager.default.createFile(atPath: temporaryFilePath, contents: nil, attributes: nil)
    let fileHandle = FileHandle(forWritingAtPath: temporaryFilePath)!

    let logger = FBControlCoreLoggerFactory.logger(toFileDescriptor: fileHandle.fileDescriptor, closeOnEndOfFile: false)
    logger.log("Some content")
    fileHandle.synchronizeFile()
    fileHandle.closeFile()

    var error: NSError?
    let fileContent = try? String(contentsOfFile: temporaryFilePath, encoding: .utf8)
    XCTAssertNotNil(fileContent)
    XCTAssertTrue(fileContent!.hasSuffix("Some content\n"), "Unexpected fileContent: \(fileContent!)")
  }

  func testLoggingToConsumer() {
    let consumer = FBDataBuffer.consumableBuffer()
    var logger = FBControlCoreLoggerFactory.logger(to: consumer)

    logger.log("HELLO")
    logger.log("WORLD")

    XCTAssertEqual(consumer.consumeLineString(), "HELLO")
    XCTAssertEqual(consumer.consumeLineString(), "WORLD")

    logger = logger.withName("foo")

    logger.log("HELLO")
    logger.log("WORLD")

    XCTAssertEqual(consumer.consumeLineString(), "[foo] HELLO")
    XCTAssertEqual(consumer.consumeLineString(), "[foo] WORLD")
  }

  func testThreadSafetyOfConsumableLogger() {
    let consumer = FBDataBuffer.consumableBuffer()
    let logger = FBControlCoreLoggerFactory.logger(to: consumer)

    let group = DispatchGroup()
    let queue = DispatchQueue.global(qos: .userInitiated)
    queue.async(group: group) { logger.log("1") }
    queue.async(group: group) { logger.log("2") }
    queue.async(group: group) { logger.log("3") }
    group.wait()

    let expected = NSSet(array: ["1", "2", "3", ""])
    let actual = NSSet(array: consumer.lines())

    XCTAssertEqual(expected, actual)
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

@Suite
struct ControlCoreLoggerTests {
  @Test
  func loggingToFileDescriptor() throws {
    let filename = "\(UUID().uuidString).log"
    let temporaryFilePath = NSTemporaryDirectory().appending(filename)
    FileManager.default.createFile(atPath: temporaryFilePath, contents: nil, attributes: nil)
    let fileHandle = FileHandle(forWritingAtPath: temporaryFilePath)!

    let logger = FBControlCoreLoggerFactory.logger(toFileDescriptor: fileHandle.fileDescriptor, closeOnEndOfFile: false)
    logger.log("Some content")
    fileHandle.synchronizeFile()
    fileHandle.closeFile()

    let fileContent = try #require(try? String(contentsOfFile: temporaryFilePath, encoding: .utf8))
    #expect(fileContent.hasSuffix("Some content\n"), "Unexpected fileContent: \(fileContent)")
  }

  @Test
  func loggingToConsumer() {
    let consumer = FBDataBuffer.consumableBuffer()
    var logger = FBControlCoreLoggerFactory.logger(to: consumer)

    logger.log("HELLO")
    logger.log("WORLD")

    #expect(consumer.consumeLineString() == "HELLO")
    #expect(consumer.consumeLineString() == "WORLD")

    logger = logger.withName("foo")

    logger.log("HELLO")
    logger.log("WORLD")

    #expect(consumer.consumeLineString() == "[foo] HELLO")
    #expect(consumer.consumeLineString() == "[foo] WORLD")
  }

  @Test
  func threadSafetyOfConsumableLogger() {
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

    #expect(expected == actual)
  }

  @Test
  func systemLoggerLevelFollowsDebugLogging() {
    let info = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false)
    let debug = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: true)

    #expect(info.level == .info)
    #expect(debug.level == .debug)
  }
}

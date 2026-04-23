/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Disabled during swift-format 6.3 rollout, feel free to remove:
// swift-format-ignore-file: OrderedImports

import XCTest

@testable import FBControlCore

final class FBFileWriterTests: XCTestCase {

  func testNonBlockingCloseOfPipe() throws {
    let pipe = Pipe()
    var writeError: NSError?
    guard let writer = FBFileWriter.asyncWriter(withFileDescriptor: pipe.fileHandleForWriting.fileDescriptor, closeOnEndOfFile: true, error: &writeError) else {
      throw writeError!
    }

    let expected = "Foo Bar Baz".data(using: .utf8)!
    writer.consumeData(expected)

    let actual = pipe.fileHandleForReading.availableData
    XCTAssertEqual(expected, actual)

    writer.consumeEndOfFile()
    try writer.finishedConsuming.`await`()

    pipe.fileHandleForWriting.closeFile()
    pipe.fileHandleForReading.closeFile()
  }

  func testNonBlockingClose() throws {
    let filePath = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
    XCTAssertTrue(FileManager.default.createFile(atPath: filePath, contents: nil, attributes: nil))
    let fileHandle = FileHandle(forWritingAtPath: filePath)
    XCTAssertNotNil(fileHandle)
    var writeError: NSError?
    guard let writer = FBFileWriter.asyncWriter(withFileDescriptor: fileHandle!.fileDescriptor, closeOnEndOfFile: true, error: &writeError) else {
      throw writeError!
    }

    let data = "Foo Bar Baz".data(using: .utf8)!
    writer.consumeData(data)
    writer.consumeEndOfFile()
  }

  func testOpeningAFifoAtBothEndsAsynchronously() throws {
    let consumer = FBDataBuffer.accumulatingBuffer()

    let fifoPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
    let status = mkfifo(fifoPath, S_IWUSR | S_IRUSR)
    XCTAssertEqual(status, 0)

    let writerFuture = FBFileWriter.asyncWriter(forFilePath: fifoPath)
    let readerFuture = FBFileReader.reader(withFilePath: fifoPath, consumer: consumer, logger: nil)
    let results = try FBFuture<AnyObject>.combine([writerFuture as! FBFuture<AnyObject>, readerFuture as! FBFuture<AnyObject>]).`await`() as NSArray?
    XCTAssertNotNil(results)

    // swiftlint:disable force_cast
    let writer = results![0] as! FBDataConsumer
    let reader = results![1] as! FBFileReader
    // swiftlint:enable force_cast

    try reader.startReading().`await`()

    writer.consumeData("HELLO\n".data(using: .utf8)!)
    writer.consumeData("THERE\n".data(using: .utf8)!)
    writer.consumeEndOfFile()

    try reader.stopReading().`await`()

    try consumer.finishedConsuming.`await`()
  }
}

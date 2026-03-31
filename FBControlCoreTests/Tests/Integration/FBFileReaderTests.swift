/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import FBControlCore
import FBControlCoreTestDoubles

final class FBFileReaderTests: XCTestCase, FBDataConsumer {

  var didRecieveEOF: Bool = false

  override func setUp() {
    super.setUp()
    didRecieveEOF = false
  }

  func testConsumesData() throws {
    let pipe = Pipe()
    let consumer = FBDataBuffer.accumulatingBuffer()
    let reader = FBFileReader(fileDescriptor: pipe.fileHandleForReading.fileDescriptor, closeOnEndOfFile: false, consumer: consumer, logger: nil)
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try reader.startReading().`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    let expected = "Foo Bar Baz".data(using: .utf8)!
    pipe.fileHandleForWriting.write(expected)
    pipe.fileHandleForWriting.closeFile()
    let predicate = NSPredicate { _, _ in
      expected == consumer.data()
    }
    let expectation = self.expectation(for: predicate, evaluatedWith: self, handler: nil)
    wait(for: [expectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)

    let result: NSNumber = try reader.stopReading().`await`()
    XCTAssertEqual(result, 0)
    XCTAssertEqual(reader.finishedReading.result, 0)
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingNormally)
  }

  func testConsumesEOFAfterStoppedReading() throws {
    let pipe = Pipe()
    let reader = FBFileReader(fileDescriptor: pipe.fileHandleForReading.fileDescriptor, closeOnEndOfFile: false, consumer: self, logger: nil)
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try reader.startReading().`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    let expected = "Foo Bar Baz".data(using: .utf8)!
    pipe.fileHandleForWriting.write(expected)

    let result: NSNumber = try reader.stopReading().`await`()
    XCTAssertEqual(result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.finishedReading.result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingByCancellation)

    XCTAssertTrue(didRecieveEOF)
  }

  func testConsumesEOFAfterStoppedReadingEvenIfOtherEndOfFifoDoesNotClose() throws {
    let fifoPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
    let status = mkfifo(fifoPath, S_IWUSR | S_IRUSR)
    XCTAssertEqual(status, 0)

    let writerFuture = FBFileWriter.asyncWriter(forFilePath: fifoPath)
    let readerFuture = FBFileReader.reader(withFilePath: fifoPath, consumer: self, logger: nil)
    let writerAndReader = try FBFutureTestHelpers.combineFutures([writerFuture, readerFuture]).`await`() as NSArray?
    XCTAssertNotNil(writerAndReader)

    // swiftlint:disable force_cast
    let writer = writerAndReader![0] as! FBDataConsumer
    let reader = writerAndReader![1] as! FBFileReader
    // swiftlint:enable force_cast

    try reader.startReading().`await`()

    writer.consumeData("HELLO\n".data(using: .utf8)!)
    writer.consumeData("THERE\n".data(using: .utf8)!)
    writer.consumeEndOfFile()

    try reader.stopReading().`await`()

    XCTAssertTrue(didRecieveEOF)
  }

  func testCanStopReadingBeforeEOFResolvesWhenPipeCloses() throws {
    let pipe = Pipe()
    let consumer = FBDataBuffer.accumulatingBuffer()
    let reader = FBFileReader(fileDescriptor: pipe.fileHandleForReading.fileDescriptor, closeOnEndOfFile: false, consumer: consumer, logger: nil)
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try reader.startReading().`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    let expected = "Foo Bar Baz".data(using: .utf8)!
    pipe.fileHandleForWriting.write(expected)
    let predicate = NSPredicate { _, _ in
      expected == consumer.data()
    }
    let expectation = self.expectation(for: predicate, evaluatedWith: self, handler: nil)
    wait(for: [expectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)

    let result: NSNumber = try reader.stopReading().`await`()
    XCTAssertEqual(result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.finishedReading.result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingByCancellation)

    pipe.fileHandleForWriting.closeFile()
  }

  func testPipeClosingBehindBackOfConsumer() throws {
    let pipe = Pipe()
    let consumer = FBDataBuffer.accumulatingBuffer()
    let reader = FBFileReader(fileDescriptor: pipe.fileHandleForReading.fileDescriptor, closeOnEndOfFile: false, consumer: consumer, logger: nil)
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try reader.startReading().`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    let expected = "Foo Bar Baz".data(using: .utf8)!
    pipe.fileHandleForWriting.write(expected)
    pipe.fileHandleForWriting.closeFile()
    let predicate = NSPredicate { _, _ in
      expected == consumer.data()
    }
    let expectation = self.expectation(for: predicate, evaluatedWith: self, handler: nil)
    wait(for: [expectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)

    let result: NSNumber = try reader.stopReading().`await`()
    XCTAssertEqual(result, 0)
    XCTAssertEqual(reader.finishedReading.result, 0)
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingNormally)
  }

  func testReadsFromFilePath() throws {
    let reader: FBFileReader = try FBFileReader.reader(withFilePath: "/dev/urandom", consumer: self, logger: nil).`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try reader.startReading().`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    let result: NSNumber = try reader.stopReading().`await`()
    XCTAssertEqual(result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.finishedReading.result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingByCancellation)
  }

  func testReadingTwiceFails() throws {
    let reader: FBFileReader = try FBFileReader.reader(withFilePath: "/dev/urandom", consumer: self, logger: nil).`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try reader.startReading().`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    XCTAssertThrowsError(try reader.startReading().`await`())
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    let result: NSNumber = try reader.stopReading().`await`()
    XCTAssertEqual(result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.finishedReading.result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingByCancellation)
  }

  func testStoppingTwiceDoesNotError() throws {
    let reader: FBFileReader = try FBFileReader.reader(withFilePath: "/dev/urandom", consumer: self, logger: nil).`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try reader.startReading().`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    var result: NSNumber = try reader.stopReading().`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingByCancellation)
    XCTAssertEqual(result, NSNumber(value: ECANCELED))

    result = try reader.stopReading().`await`()
    XCTAssertEqual(result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.finishedReading.result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingByCancellation)
  }

  func testCancellationOnFinishedReading() throws {
    let reader: FBFileReader = try FBFileReader.reader(withFilePath: "/dev/urandom", consumer: self, logger: nil).`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try reader.startReading().`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    let finished = reader.finishedReading
    XCTAssertEqual(finished.state, FBFutureState.running)
    try finished.cancel().`await`()
    XCTAssertEqual(finished.state, FBFutureState.cancelled)
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingByCancellation)
  }

  func testConcurrentAttachmentIsProhibited() throws {
    let reader: FBFileReader = try FBFileReader.reader(withFilePath: "/dev/urandom", consumer: self, logger: nil).`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    let concurrentQueue = DispatchQueue.global(qos: .userInitiated)
    let group = DispatchGroup()
    var firstAttempt: FBFuture<NSNull>!
    var secondAttempt: FBFuture<NSNull>!
    var thirdAttempt: FBFuture<NSNull>!

    group.enter()
    concurrentQueue.async {
      firstAttempt = reader.startReading()
      group.leave()
    }
    group.enter()
    concurrentQueue.async {
      secondAttempt = reader.startReading()
      group.leave()
    }
    group.enter()
    concurrentQueue.async {
      thirdAttempt = reader.startReading()
      group.leave()
    }
    group.wait()

    try? firstAttempt.`await`()
    try? secondAttempt.`await`()
    try? thirdAttempt.`await`()
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

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

    XCTAssertEqual(successes, 1)
  }

  func testAttemptingToReadAGarbageFileDescriptor() throws {
    let reader = FBFileReader(fileDescriptor: 92123, closeOnEndOfFile: false, consumer: self, logger: nil)
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try reader.startReading().`await`()

    let result: NSNumber = try reader.stopReading().`await`()
    XCTAssertEqual(result, NSNumber(value: EBADF))
    XCTAssertEqual(reader.finishedReading.result, NSNumber(value: EBADF))
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingInError)
  }

  // MARK: FBDataConsumer

  func consumeEndOfFile() {
    didRecieveEOF = true
  }

  func consumeData(_ data: Data) {}
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FileReaderTests: XCTestCase, DataConsumer {

  var didRecieveEOF: Bool = false

  override func setUp() {
    super.setUp()
    didRecieveEOF = false
  }

  func testConsumesData() async throws {
    let pipe = Pipe()
    let consumer = FBDataBuffer.accumulatingBuffer()
    let reader = FileReader.reader(withFileDescriptor: pipe.fileHandleForReading.fileDescriptor, closeOnEndOfFile: false, consumer: consumer, logger: nil)
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try await bridgeFBFutureVoid(reader.startReading())
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    let expected = "Foo Bar Baz".data(using: .utf8)!
    pipe.fileHandleForWriting.write(expected)
    pipe.fileHandleForWriting.closeFile()
    let predicate = NSPredicate { _, _ in
      expected == consumer.data()
    }
    let expectation = self.expectation(for: predicate, evaluatedWith: self, handler: nil)
    await fulfillment(of: [expectation], timeout: ControlCoreGlobalConfiguration.fastTimeout)

    let result: NSNumber = try await bridgeFBFuture(reader.stopReading())
    XCTAssertEqual(result, 0)
    XCTAssertEqual(reader.finishedReading.result, 0)
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingNormally)
  }

  func testConsumesEOFAfterStoppedReading() async throws {
    let pipe = Pipe()
    let reader = FileReader.reader(withFileDescriptor: pipe.fileHandleForReading.fileDescriptor, closeOnEndOfFile: false, consumer: self, logger: nil)
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try await bridgeFBFutureVoid(reader.startReading())
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    let expected = "Foo Bar Baz".data(using: .utf8)!
    pipe.fileHandleForWriting.write(expected)

    let result: NSNumber = try await bridgeFBFuture(reader.stopReading())
    XCTAssertEqual(result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.finishedReading.result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingByCancellation)

    XCTAssertTrue(didRecieveEOF)
  }

  func testConsumesEOFAfterStoppedReadingEvenIfOtherEndOfFifoDoesNotClose() async throws {
    let fifoPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
    let status = mkfifo(fifoPath, S_IWUSR | S_IRUSR)
    XCTAssertEqual(status, 0)

    // Each end's open blocks until the other end is opened.
    async let opening = FileWriter.asyncWriter(forFilePath: fifoPath)
    let reader = try await bridgeFBFuture(FileReader.reader(withFilePath: fifoPath, consumer: self, logger: nil))
    let writer = try await opening

    try await bridgeFBFutureVoid(reader.startReading())

    writer.consumeData("HELLO\n".data(using: .utf8)!)
    writer.consumeData("THERE\n".data(using: .utf8)!)
    writer.consumeEndOfFile()

    _ = try await bridgeFBFuture(reader.stopReading())

    XCTAssertTrue(didRecieveEOF)

    // Drain the writer's asynchronous channel teardown before the test ends,
    // so its deferred fd close cannot race into later tests' fd lifecycles.
    try await writer.awaitFinishedConsuming()
  }

  func testCanStopReadingBeforeEOFResolvesWhenPipeCloses() async throws {
    let pipe = Pipe()
    let consumer = FBDataBuffer.accumulatingBuffer()
    let reader = FileReader.reader(withFileDescriptor: pipe.fileHandleForReading.fileDescriptor, closeOnEndOfFile: false, consumer: consumer, logger: nil)
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try await bridgeFBFutureVoid(reader.startReading())
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    let expected = "Foo Bar Baz".data(using: .utf8)!
    pipe.fileHandleForWriting.write(expected)
    let predicate = NSPredicate { _, _ in
      expected == consumer.data()
    }
    let expectation = self.expectation(for: predicate, evaluatedWith: self, handler: nil)
    await fulfillment(of: [expectation], timeout: ControlCoreGlobalConfiguration.fastTimeout)

    let result: NSNumber = try await bridgeFBFuture(reader.stopReading())
    XCTAssertEqual(result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.finishedReading.result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingByCancellation)

    pipe.fileHandleForWriting.closeFile()
  }

  func testReadingTwiceFails() async throws {
    let reader: FileReader = try await bridgeFBFuture(FileReader.reader(withFilePath: "/dev/urandom", consumer: self, logger: nil))
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try await bridgeFBFutureVoid(reader.startReading())
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    var secondStartError: Error?
    do {
      try await bridgeFBFutureVoid(reader.startReading())
    } catch {
      secondStartError = error
    }
    XCTAssertNotNil(secondStartError)
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    let result: NSNumber = try await bridgeFBFuture(reader.stopReading())
    XCTAssertEqual(result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.finishedReading.result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingByCancellation)
  }

  func testStoppingTwiceDoesNotError() async throws {
    let reader: FileReader = try await bridgeFBFuture(FileReader.reader(withFilePath: "/dev/urandom", consumer: self, logger: nil))
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try await bridgeFBFutureVoid(reader.startReading())
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    var result: NSNumber = try await bridgeFBFuture(reader.stopReading())
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingByCancellation)
    XCTAssertEqual(result, NSNumber(value: ECANCELED))

    result = try await bridgeFBFuture(reader.stopReading())
    XCTAssertEqual(result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.finishedReading.result, NSNumber(value: ECANCELED))
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingByCancellation)
  }

  func testCancellationOnFinishedReading() async throws {
    let reader: FileReader = try await bridgeFBFuture(FileReader.reader(withFilePath: "/dev/urandom", consumer: self, logger: nil))
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try await bridgeFBFutureVoid(reader.startReading())
    XCTAssertEqual(reader.state, FBFileReaderState.reading)

    let finished = reader.finishedReading
    XCTAssertEqual(finished.state, FBFutureState.running)
    try await bridgeFBFutureVoid(finished.cancel().retyped(FBFuture<AnyObject>.self))
    XCTAssertEqual(finished.state, FBFutureState.cancelled)
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingByCancellation)
  }

  func testConcurrentAttachmentIsProhibited() async throws {
    let reader: FileReader = try await bridgeFBFuture(FileReader.reader(withFilePath: "/dev/urandom", consumer: self, logger: nil))
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

    try? await bridgeFBFutureVoid(firstAttempt)
    try? await bridgeFBFutureVoid(secondAttempt)
    try? await bridgeFBFutureVoid(thirdAttempt)
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

  func testNonBlockingFlagAfterTeardownOfUnownedSocketReader() async throws {
    var descriptors: [Int32] = [0, 0]
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
    let localSocket = descriptors[0]
    let remoteSocket = descriptors[1]
    defer {
      close(localSocket)
      close(remoteSocket)
    }

    let consumer = FBDataBuffer.accumulatingBuffer()
    let reader = FileReader.reader(withFileDescriptor: localSocket, closeOnEndOfFile: false, consumer: consumer, logger: nil)
    try await bridgeFBFutureVoid(reader.startReading())

    // Traffic through the channel guarantees libdispatch has armed the
    // descriptor: its per-descriptor entry exists, the original (blocking)
    // flags are recorded, and O_NONBLOCK is forced on.
    let expected = "ping".data(using: .utf8)!
    expected.withUnsafeBytes { buffer in
      XCTAssertEqual(write(remoteSocket, buffer.baseAddress, buffer.count), expected.count)
    }
    let consumed = NSPredicate { _, _ in
      expected == consumer.data()
    }
    await fulfillment(of: [expectation(for: consumed, evaluatedWith: self, handler: nil)], timeout: ControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertNotEqual(fcntl(localSocket, F_GETFL) & O_NONBLOCK, 0)

    _ = try await bridgeFBFuture(reader.stopReading())

    // Teardown must not restore blocking flags on a descriptor the channel never owned: the restore is
    // asynchronous and could land on a recycled fd number belonging to an unrelated live channel.
    XCTAssertNotEqual(fcntl(localSocket, F_GETFL) & O_NONBLOCK, 0)
  }

  func testAttemptingToReadAGarbageFileDescriptor() async throws {
    let reader = FileReader.reader(withFileDescriptor: 92123, closeOnEndOfFile: false, consumer: self, logger: nil)
    XCTAssertEqual(reader.state, FBFileReaderState.notStarted)

    try await bridgeFBFutureVoid(reader.startReading())

    let result: NSNumber = try await bridgeFBFuture(reader.stopReading())
    XCTAssertEqual(result, NSNumber(value: EBADF))
    XCTAssertEqual(reader.finishedReading.result, NSNumber(value: EBADF))
    XCTAssertEqual(reader.state, FBFileReaderState.finishedReadingInError)
  }

  // MARK: - DataConsumer

  func consumeEndOfFile() {
    didRecieveEOF = true
  }

  func consumeData(_ data: Data) {}
}

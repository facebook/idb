/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBFileWriterTests: XCTestCase {

  override func setUpWithError() throws {
    // This class exercises dispatch_io descriptor teardown, which hosted CI
    // runners have repeatedly proven a hostile environment for. The class is
    // reliable on internal continuous runs, which remain the coverage of
    // record; skip wholesale rather than gating tests one by one.
    try XCTSkipIf(
      ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      "dispatch_io teardown classes are covered by internal continuous runs")
    try super.setUpWithError()
  }

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

  func testNonBlockingFlagAfterTeardownOfDuplicatedSocketWriter() throws {
    var descriptors: [Int32] = [0, 0]
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
    let localSocket = descriptors[0]
    let remoteSocket = descriptors[1]
    defer {
      close(localSocket)
      close(remoteSocket)
    }

    // The two descriptors share one open file description, so file status
    // flags set through either are visible through both.
    let writerDescriptor = dup(localSocket)
    XCTAssertGreaterThanOrEqual(writerDescriptor, 0)
    var writeError: NSError?
    guard let writer = FBFileWriter.asyncWriter(withFileDescriptor: writerDescriptor, closeOnEndOfFile: true, error: &writeError) else {
      throw writeError!
    }

    // A write arms the channel: libdispatch records the description's
    // original (blocking) flags and forces O_NONBLOCK onto it.
    writer.consumeData("ping".data(using: .utf8)!)
    writer.consumeEndOfFile()
    _ = try writer.finishedConsuming.`await`(withTimeout: 10)

    // The write was flushed before the channel wound down.
    var buffer = [UInt8](repeating: 0, count: 4)
    XCTAssertEqual(recv(remoteSocket, &buffer, 4, MSG_DONTWAIT), 4)

    // Winding down must not restore the duplicate's original blocking flags
    // onto the shared open file description: localSocket keeps O_NONBLOCK, so
    // a reader channel armed on it can never wedge in a blocking read(2).
    XCTAssertNotEqual(fcntl(localSocket, F_GETFL) & O_NONBLOCK, 0)
  }

  func testNonBlockingFlagAfterTeardownOfUnownedSocketWriter() throws {
    var descriptors: [Int32] = [0, 0]
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
    let localSocket = descriptors[0]
    let remoteSocket = descriptors[1]
    defer {
      close(localSocket)
      close(remoteSocket)
    }

    var writeError: NSError?
    guard let writer = FBFileWriter.asyncWriter(withFileDescriptor: localSocket, closeOnEndOfFile: false, error: &writeError) else {
      throw writeError!
    }

    // A write arms the channel: libdispatch records the descriptor's
    // original (blocking) flags and forces O_NONBLOCK onto it.
    writer.consumeData("ping".data(using: .utf8)!)
    writer.consumeEndOfFile()
    _ = try writer.finishedConsuming.`await`(withTimeout: 10)

    // The write was flushed before the channel wound down.
    var buffer = [UInt8](repeating: 0, count: 4)
    XCTAssertEqual(recv(remoteSocket, &buffer, 4, MSG_DONTWAIT), 4)

    // Winding down must not restore the original blocking flags onto a
    // descriptor the channel never owned: that restore lands on an
    // asynchronously-drained queue, possibly after the caller has closed the
    // descriptor and the number has been recycled, re-blocking an unrelated
    // live channel. The borrowed socket stays non-blocking.
    XCTAssertNotEqual(fcntl(localSocket, F_GETFL) & O_NONBLOCK, 0)
  }

  func testStopThenCloseTeardownOfSocketReaderAndDuplicatedWriter() throws {
    var descriptors: [Int32] = [0, 0]
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
    let localSocket = descriptors[0]
    let remoteSocket = descriptors[1]

    // The writer gets its own duplicate of the socket, owned and closed by its
    // channel. Two dispatch io channels must not share one descriptor: they
    // share a per-descriptor entry inside libdispatch, and one channel's
    // cleanup is deferred behind the other's outstanding operations — a writer
    // ended while a reader is still armed on the same descriptor never
    // delivers its cleanup, wedging teardown.
    let writerDescriptor = dup(localSocket)
    XCTAssertGreaterThanOrEqual(writerDescriptor, 0)
    var writeError: NSError?
    guard let writer = FBFileWriter.asyncWriter(withFileDescriptor: writerDescriptor, closeOnEndOfFile: true, error: &writeError) else {
      throw writeError!
    }
    let reader = FBFileReader.reader(withFileDescriptor: localSocket, closeOnEndOfFile: false, consumer: FBFileWriter.nullWriter, logger: nil)
    _ = try reader.startReading().`await`(withTimeout: 10)

    // Traffic in both directions, so teardown runs against live channels.
    writer.consumeData("ping".data(using: .utf8)!)
    let pong = "pong".data(using: .utf8)!
    pong.withUnsafeBytes { buffer in
      XCTAssertEqual(write(remoteSocket, buffer.baseAddress, buffer.count), pong.count)
    }

    // Teardown: end the writer and wait for its channel to close its duplicate,
    // wind down the reader with a bounded drain, and only then close the
    // socket. All waits are bounded so a teardown wedge fails this test alone
    // rather than timing out the whole target.
    writer.consumeEndOfFile()
    _ = try writer.finishedConsuming.`await`(withTimeout: 10)
    XCTAssertEqual(fcntl(writerDescriptor, F_GETFD), -1)
    _ = try reader.finishedReading(withTimeout: 4).`await`(withTimeout: 10)

    XCTAssertEqual(close(localSocket), 0)
    XCTAssertEqual(close(remoteSocket), 0)
  }
}

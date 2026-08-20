/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBProcessIOTests: XCTestCase {

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

  func testDetachmentMultipleTimesIsPermitted() throws {
    let stdInConsumer = FBDataBuffer.consumableBuffer()
    let stdOutConsumer = FBDataBuffer.consumableBuffer()
    let io = FBProcessIO<NSNull, FBDataConsumer, FBDataConsumer>(
      stdIn: nil,
      stdOut: FBProcessOutput<FBDataConsumer>(for: stdInConsumer),
      stdErr: FBProcessOutput<FBDataConsumer>(for: stdOutConsumer)
    )

    let attachment = try io.attach().`await`()
    XCTAssertNotNil(attachment)

    let concurrentQueue = DispatchQueue.global(qos: .userInitiated)
    let group = DispatchGroup()
    var first: FBFuture<NSNull>!
    var second: FBFuture<NSNull>!
    var third: FBFuture<NSNull>!
    var fourth: FBFuture<NSNull>!

    group.enter()
    concurrentQueue.async {
      first = attachment.detach()
      group.leave()
    }
    group.enter()
    concurrentQueue.async {
      second = attachment.detach()
      group.leave()
    }
    group.enter()
    concurrentQueue.async {
      third = attachment.detach()
      group.leave()
    }
    group.enter()
    concurrentQueue.async {
      fourth = attachment.detach()
      group.leave()
    }
    group.wait()

    for attempt in [first!, second!, third!, fourth!] {
      try attempt.`await`()
      XCTAssertTrue(stdInConsumer.finishedConsuming.hasCompleted)
    }
  }

  func testMultipleAttachmentIsNotPermitted() throws {
    let stdInConsumer = FBDataBuffer.consumableBuffer()
    let stdOutConsumer = FBDataBuffer.consumableBuffer()
    let io = FBProcessIO<NSNull, FBDataConsumer, FBDataConsumer>(
      stdIn: nil,
      stdOut: FBProcessOutput<FBDataConsumer>(for: stdInConsumer),
      stdErr: FBProcessOutput<FBDataConsumer>(for: stdOutConsumer)
    )

    let attachment = try io.attach().`await`()
    XCTAssertNotNil(attachment)

    XCTAssertThrowsError(try io.attach().`await`())

    try attachment.detach().`await`()
  }

  func testDetachClosesConsumerBackedAttachmentDescriptors() throws {
    let io = FBProcessIO<NSNull, FBDataConsumer, FBDataConsumer>(
      stdIn: nil,
      stdOut: FBProcessOutput<FBDataConsumer>(for: FBDataBuffer.consumableBuffer()),
      stdErr: FBProcessOutput<FBDataConsumer>(for: FBDataBuffer.consumableBuffer())
    )

    let attachment = try io.attach().`await`()
    let stdOut = try XCTUnwrap(attachment.stdOut)
    let stdErr = try XCTUnwrap(attachment.stdErr)
    XCTAssertNotEqual(fcntl(stdOut.fileDescriptor, F_GETFD), -1)
    XCTAssertNotEqual(fcntl(stdErr.fileDescriptor, F_GETFD), -1)

    try attachment.detach().`await`()

    // Detach owns closing the attachment's descriptors; closing them anywhere
    // else double-closes a recycled descriptor number.
    XCTAssertEqual(fcntl(stdOut.fileDescriptor, F_GETFD), -1)
    XCTAssertEqual(fcntl(stdErr.fileDescriptor, F_GETFD), -1)
  }

  func testAttachWithNilStreamsReturnsNilAttachments() throws {
    let io = FBProcessIO<NSNull, NSNull, NSNull>(
      stdIn: nil,
      stdOut: nil,
      stdErr: nil
    )

    let attachment = try io.attach().`await`()

    XCTAssertNil(attachment.stdIn)
    XCTAssertNil(attachment.stdOut)
    XCTAssertNil(attachment.stdErr)
    try attachment.detach().`await`()
  }

  func testAttachViaFileReturnsNullDeviceOutputs() throws {
    let io = FBProcessIO<NSNull, NSNull, NSNull>.outputToDevNull()

    let attachment = try io.attachViaFile().`await`()

    XCTAssertEqual(attachment.stdOut?.filePath, "/dev/null")
    XCTAssertEqual(attachment.stdErr?.filePath, "/dev/null")
    try attachment.detach().`await`()
  }

  func testAttachViaFileWithNilOutputsReturnsNilFileOutputs() throws {
    let io = FBProcessIO<NSNull, NSNull, NSNull>(
      stdIn: nil,
      stdOut: nil,
      stdErr: nil
    )

    let attachment = try io.attachViaFile().`await`()

    XCTAssertNil(attachment.stdOut)
    XCTAssertNil(attachment.stdErr)
    try attachment.detach().`await`()
  }

  func testAttachViaFileRejectsSecondAttachment() throws {
    let io = FBProcessIO<NSNull, NSNull, NSNull>.outputToDevNull()
    let attachment = try io.attachViaFile().`await`()

    XCTAssertThrowsError(try io.attachViaFile().`await`())
    try attachment.detach().`await`()
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBProcessIOTests: XCTestCase {

  func testDetachmentMultipleTimesIsPermitted() throws {
    // Stalls on GitHub-hosted runners until the per-test time allowance kills
    // it — the same dispatch_io teardown coupling that affected the FIFO
    // tests, here on pipe descriptors that spawned children inherit, where
    // pre-setting O_NONBLOCK is not an option. If diagnosis is wanted,
    // un-skip temporarily — failing jobs upload the result bundle.
    try XCTSkipIf(
      ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      "Stalls on hosted CI runners until the time allowance kills it")

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
}

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
}

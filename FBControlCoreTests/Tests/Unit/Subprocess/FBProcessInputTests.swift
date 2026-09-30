/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBProcessInputTests: XCTestCase {

  func testConsumerInput_BytesWrittenBeforeTheProcessStarts() async throws {
    let rawInput = FBProcessInput<NSObject>.fromConsumer()
    let consumer = rawInput.contents
    consumer.consumeData(Data("early".utf8))

    let process = try await bridgeFBFuture(
      FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath("/bin/cat", arguments: [])
        .withStdIn(rawInput.retyped(FBProcessInput<AnyObject>.self))
        .withStdOutInMemoryAsString()
        .start())
    consumer.consumeData(Data(" late".utf8))
    consumer.consumeEndOfFile()
    _ = try await bridgeFBFuture(process.exited(withCodes: [0]))

    XCTAssertEqual(process.stdOut as? String, "early late")
  }

  func testConsumerInput_BytesWrittenAfterDetachAreNotKept() async throws {
    let rawInput = FBProcessInput<NSObject>.fromConsumer()
    let input = rawInput as NSObject
    let consumer = rawInput.contents
    _ = try await bridgeFBFuture(rawInput.attach())
    _ = try await bridgeFBFuture(rawInput.detach())
    // The writer is released on the work queue after the detach future resolves.
    let deadline = Date().addingTimeInterval(5)
    while input.value(forKey: "writer") != nil && Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertNil(input.value(forKey: "writer"))

    consumer.consumeData(Data("after".utf8))

    XCTAssertNil(input.value(forKey: "pendingData"))
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBControlCore
import GRPCCore
import IDBGRPCSwift
import XCTest

private final class ScriptedTail: TailOperation, @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  var wasCancelled: Bool { lock.withLock { cancelled } }

  func cancel() async throws {
    lock.withLock { cancelled = true }
  }
}

private struct StreamEnded: Error {}

final class TailMethodHandlerTests: XCTestCase {

  func testAStopCancelsTheTail() async throws {
    let tail = ScriptedTail()
    try await TailMethodHandler.tail(send: { _ in }, awaitStop: {}, start: { _ in tail })
    XCTAssertTrue(tail.wasCancelled)
  }

  func testAStreamEndingWithoutAStopFailsTheCall() async throws {
    let tail = ScriptedTail()
    do {
      try await TailMethodHandler.tail(send: { _ in }, awaitStop: { throw StreamEnded() }, start: { _ in tail })
      XCTFail("the call outlived its request stream")
    } catch is StreamEnded {}
    // BUG: the tail process is left running when the client goes away without a stop — flipped in the following commit.
    XCTAssertFalse(tail.wasCancelled)
  }
}

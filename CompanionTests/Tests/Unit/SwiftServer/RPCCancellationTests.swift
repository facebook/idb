/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import GRPCCore
import XCTest

final class RPCCancellationTests: XCTestCase {
  func testCompletedOperationDoesNotWaitForDisconnect() async throws {
    let cancellation = ServerContext.RPCCancellationHandle()
    try await withRPCCancellation(cancellation) {}
    XCTAssertFalse(cancellation.isCancelled)
  }

  func testAlreadyCancelledRPCDoesNotStartOperation() async {
    let cancellation = ServerContext.RPCCancellationHandle()
    cancellation.cancel()
    do {
      try await withRPCCancellation(cancellation) {
        XCTFail("Cancelled RPC must not begin the operation")
      }
      XCTFail("Expected cancellation")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testDisconnectCancelsOperationAndJoinsCleanup() async throws {
    let cancellation = ServerContext.RPCCancellationHandle()
    let (started, continuation) = AsyncStream<Void>.makeStream()
    let cleanup = CleanupState()
    async let result: Void = withRPCCancellation(cancellation) {
      continuation.yield(())
      do {
        try await Task.sleep(nanoseconds: 30_000_000_000)
      } catch {
        await cleanup.complete()
        throw error
      }
    }
    var iterator = started.makeAsyncIterator()
    _ = await iterator.next()
    cancellation.cancel()
    do {
      try await result
      XCTFail("Expected cancellation")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let completed = await cleanup.completed
    XCTAssertTrue(completed)
  }

  private actor CleanupState {
    private(set) var completed = false
    func complete() { completed = true }
  }
}

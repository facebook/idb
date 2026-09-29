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

private final class ScriptedLogOperation: LogOperation, @unchecked Sendable {
  let consumer: any DataConsumer
  let holdsOpen: Bool
  let onStop: @Sendable () -> Void

  /// The log ends at once, or with `holdsOpen` runs until its waiter is cancelled.
  init(consumer: any DataConsumer, holdsOpen: Bool, onStop: @escaping @Sendable () -> Void = {}) {
    self.consumer = consumer
    self.holdsOpen = holdsOpen
    self.onStop = onStop
  }

  func waitUntilCompleted() async throws {
    guard holdsOpen else { return }
    do {
      try await Task.sleep(nanoseconds: 60_000_000_000)
    } catch {
      onStop()
      throw error
    }
  }
}

private final class SentResponses: @unchecked Sendable {
  private let lock = NSLock()
  private var responses: [Idb_LogResponse] = []

  var all: [Idb_LogResponse] { lock.withLock { responses } }

  func append(_ response: Idb_LogResponse) {
    lock.withLock { responses.append(response) }
  }
}

final class LogMethodHandlerTests: XCTestCase {

  func testTheLogIsForwardedUntilItEnds() async throws {
    let sent = SentResponses()
    try await LogMethodHandler.tail(cancellation: ServerContext.RPCCancellationHandle(), send: { sent.append($0) }) { consumer in
      consumer.consumeData(Data("one".utf8))
      consumer.consumeData(Data("two".utf8))
      return ScriptedLogOperation(consumer: consumer, holdsOpen: false)
    }
    XCTAssertEqual(sent.all, [.with { $0.output = Data("one".utf8) }, .with { $0.output = Data("two".utf8) }])
  }

  func testAFailedWriteEndsTheCall() async throws {
    struct WriteFailed: Error {}
    do {
      try await LogMethodHandler.tail(cancellation: ServerContext.RPCCancellationHandle(), send: { _ in throw WriteFailed() }) { consumer in
        consumer.consumeData(Data("one".utf8))
        return ScriptedLogOperation(consumer: consumer, holdsOpen: true)
      }
      XCTFail("the call outlived its failed write")
    } catch is WriteFailed {}
  }

  // gRPC reports a client going away through the RPC's cancellation handle, not by cancelling the
  // handler's task.
  func testAClientGoingAwayStopsTheLog() async throws {
    let started = expectation(description: "the log starts")
    let stopped = expectation(description: "the log stops")
    let cancellation = ServerContext.RPCCancellationHandle()
    let call = Task {
      try await LogMethodHandler.tail(cancellation: cancellation, send: { _ in }) { consumer in
        started.fulfill()
        return ScriptedLogOperation(consumer: consumer, holdsOpen: true) { stopped.fulfill() }
      }
    }
    await fulfillment(of: [started], timeout: 5)
    cancellation.cancel()
    await fulfillment(of: [stopped], timeout: 1)
    do {
      try await call.value
      XCTFail("the call outlived its cancellation")
    } catch is CancellationError {}
  }
}

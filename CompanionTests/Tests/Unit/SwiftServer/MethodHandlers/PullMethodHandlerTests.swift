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

private let logger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false)

private final class ScriptedFilePuller: FilePulling, @unchecked Sendable {
  let temporaryDirectory = TemporaryDirectory(logger: logger)
  let holdsOpen: Bool
  let onStart: @Sendable () -> Void
  let onStop: @Sendable () -> Void

  /// A pull lands at its destination at once, or with `holdsOpen` runs until it is cancelled.
  init(holdsOpen: Bool = false, onStart: @escaping @Sendable () -> Void = {}, onStop: @escaping @Sendable () -> Void = {}) {
    self.holdsOpen = holdsOpen
    self.onStart = onStart
    self.onStop = onStop
  }

  func pull_file_path(_ path: String, destination_path destinationPath: String, containerType: String?) async throws -> String {
    onStart()
    guard holdsOpen else { return destinationPath }
    do {
      try await Task.sleep(nanoseconds: 60_000_000_000)
    } catch {
      onStop()
      throw error
    }
    return destinationPath
  }
}

private final class SentResponses: @unchecked Sendable {
  private let lock = NSLock()
  private var responses: [Idb_PullResponse] = []

  var all: [Idb_PullResponse] { lock.withLock { responses } }

  func append(_ response: Idb_PullResponse) {
    lock.withLock { responses.append(response) }
  }
}

final class PullMethodHandlerTests: XCTestCase {

  private let request = Idb_PullRequest.with {
    $0.srcPath = "Documents/file.txt"
    $0.dstPath = "/tmp/file.txt"
  }

  func testAPullToADestinationSendsWhereItLanded() async throws {
    let sent = SentResponses()
    try await PullMethodHandler.pull(request, using: ScriptedFilePuller(), logger: logger, cancellation: ServerContext.RPCCancellationHandle()) {
      sent.append($0)
    }
    XCTAssertEqual(sent.all, [.with { $0.payload = .with { $0.source = .filePath("/tmp/file.txt") } }])
  }

  // gRPC reports a client going away through the RPC's cancellation handle, not by cancelling the
  // handler's task.
  func testAClientGoingAwayStopsThePull() async throws {
    let started = expectation(description: "the pull starts")
    let stopped = expectation(description: "the pull stops")
    let puller = ScriptedFilePuller(holdsOpen: true, onStart: { started.fulfill() }, onStop: { stopped.fulfill() })
    let cancellation = ServerContext.RPCCancellationHandle()
    let request = request
    let call = Task {
      try await PullMethodHandler.pull(request, using: puller, logger: logger, cancellation: cancellation) { _ in }
    }
    await fulfillment(of: [started], timeout: 5)
    cancellation.cancel()
    // BUG: the pull outlives the RPC — flipped in the following commit.
    let result = await XCTWaiter().fulfillment(of: [stopped], timeout: 1)
    XCTAssertEqual(result, .timedOut)
    call.cancel()
    _ = await call.result
  }
}

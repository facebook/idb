/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import GRPCCore
import XCTest
import XCTestBootstrap

private final class ScriptedTestRun: XCTestRunCompletion, @unchecked Sendable {
  enum Outcome {
    case fails(Error)
    case holdsOpen(onStop: @Sendable () -> Void)
  }

  let outcome: Outcome

  init(_ outcome: Outcome) {
    self.outcome = outcome
  }

  func awaitCompletion() async throws {
    switch outcome {
    case let .fails(error):
      throw error
    case let .holdsOpen(onStop):
      do {
        try await Task.sleep(nanoseconds: 60_000_000_000)
      } catch {
        onStop()
        throw error
      }
    }
  }
}

final class XCTestRunMethodHandlerTests: XCTestCase {

  func testATestBinaryFailureStillWaitsForReporting() async throws {
    let reported = expectation(description: "reporting is awaited")
    try await XCTestRunMethodHandler.run(
      cancellation: ServerContext.RPCCancellationHandle(),
      start: { ScriptedTestRun(.fails(NSError(domain: FBTestErrorDomain, code: 1))) },
      reportingTerminated: { reported.fulfill() })
    await fulfillment(of: [reported], timeout: 0)
  }

  func testAnyOtherFailureEndsTheCall() async throws {
    let error = NSError(domain: "com.example.test", code: 1)
    do {
      try await XCTestRunMethodHandler.run(
        cancellation: ServerContext.RPCCancellationHandle(),
        start: { ScriptedTestRun(.fails(error)) },
        reportingTerminated: { XCTFail("reporting was awaited after the run failed") })
      XCTFail("the failure was swallowed")
    } catch let thrown as NSError {
      XCTAssertEqual(thrown, error)
    }
  }

  // gRPC reports a client going away through the RPC's cancellation handle, not by cancelling the
  // handler's task.
  func testAClientGoingAwayStopsTheRun() async throws {
    let started = expectation(description: "the run starts")
    let stopped = expectation(description: "the run stops")
    let cancellation = ServerContext.RPCCancellationHandle()
    let call = Task {
      try await XCTestRunMethodHandler.run(
        cancellation: cancellation,
        start: {
          started.fulfill()
          return ScriptedTestRun(.holdsOpen { stopped.fulfill() })
        },
        reportingTerminated: {})
    }
    await fulfillment(of: [started], timeout: 5)
    cancellation.cancel()
    // BUG: the run outlives the RPC — flipped in the following commit.
    let result = await XCTWaiter().fulfillment(of: [stopped], timeout: 1)
    XCTAssertEqual(result, .timedOut)
    call.cancel()
    _ = await call.result
  }
}

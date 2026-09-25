/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
@preconcurrency import FBControlCore
import FBSimulatorControl
import GRPCCore
import IDBGRPCSwift
import XCTest

private final class ScriptedQuiescenceExecutor: AccessibilityQuiescenceStreaming {
  private(set) var queries: [AccessibilityElementQuery] = []
  private(set) var parameters: [QuiescenceParameters] = []
  private(set) var backends: [UIAutomationBackend] = []
  let events: [QuiescenceEvent]
  let holdsOpen: Bool
  let onTermination: @Sendable () -> Void

  /// The stream yields `events`, then ends, or with `holdsOpen` stays open until its consumer stops.
  init(events: [QuiescenceEvent] = [], holdsOpen: Bool = false, onTermination: @escaping @Sendable () -> Void = {}) {
    self.events = events
    self.holdsOpen = holdsOpen
    self.onTermination = onTermination
  }

  func accessibility_quiescence(
    query: AccessibilityElementQuery,
    parameters: QuiescenceParameters,
    backend: UIAutomationBackend
  ) async throws -> AsyncThrowingStream<QuiescenceEvent, Error> {
    queries.append(query)
    self.parameters.append(parameters)
    backends.append(backend)
    let (events, holdsOpen, onTermination) = (events, holdsOpen, onTermination)
    return AsyncThrowingStream { continuation in
      continuation.onTermination = { _ in onTermination() }
      events.forEach { continuation.yield($0) }
      if !holdsOpen {
        continuation.finish()
      }
    }
  }

  func process_id(forBundleID bundleID: String) async throws -> pid_t {
    XCTAssertEqual(bundleID, "com.example.app")
    return 77
  }
}

final class AccessibilityQuiescenceMethodHandlerTests: XCTestCase {

  private func stream(_ request: Idb_AccessibilityQuiescenceRequest, using executor: ScriptedQuiescenceExecutor) async throws -> [Idb_AccessibilityQuiescenceResponse] {
    var responses: [Idb_AccessibilityQuiescenceResponse] = []
    try await AccessibilityQuiescenceMethodHandler.stream(request, using: executor) { responses.append($0) }
    return responses
  }

  func testNoTargetFollowsTheFrontmostApplicationOnTheExclusiveBridge() async throws {
    let executor = ScriptedQuiescenceExecutor()
    _ = try await stream(Idb_AccessibilityQuiescenceRequest(), using: executor)
    XCTAssertEqual(executor.queries, [.frontmost])
    XCTAssertEqual(executor.parameters, [QuiescenceParameters()])
    XCTAssertEqual(executor.backends, [UIAutomationBackend(resolvedName: .axBridgeExclusive)])
  }

  func testAPidOrBundleIDNamesTheApplication() async throws {
    let executor = ScriptedQuiescenceExecutor()
    _ = try await stream(.with { $0.pid = 42 }, using: executor)
    _ = try await stream(.with { $0.bundleID = "com.example.app" }, using: executor)
    XCTAssertEqual(executor.queries, [.application(pid: 42), .application(pid: 77)])
  }

  func testAPidOutOfRangeIsAnInvalidArgument() async throws {
    let executor = ScriptedQuiescenceExecutor()
    for pid: UInt64 in [0, UInt64(Int32.max) + 1] {
      do {
        _ = try await stream(.with { $0.pid = pid }, using: executor)
        XCTFail("\(pid) was accepted")
      } catch let error as RPCError {
        XCTAssertEqual(error.code, .invalidArgument)
      }
    }
    XCTAssertEqual(executor.queries, [])
  }

  func testATunableIsSentOnlyWhenSetAndZeroIsKept() async throws {
    let executor = ScriptedQuiescenceExecutor()
    _ = try await stream(.with { $0.quietWindowMs = 0 }, using: executor)
    _ = try await stream(.with { $0.busyThresholdMs = 1500 }, using: executor)
    XCTAssertEqual(executor.parameters, [QuiescenceParameters(quietWindow: 0), QuiescenceParameters(busyThreshold: 1.5)])
  }

  func testEveryEventIsForwardedInOrder() async throws {
    let executor = ScriptedQuiescenceExecutor(events: [
      .state(.busy([.runLoopIdle, .animationsInactive]), pid: 42),
      .touchesCompleted(pid: 42),
      .state(.settling, pid: 42),
      .targetChanged(pid: 43),
      .state(.quiet, pid: 43),
      .targetExited(pid: 43),
    ])
    let responses = try await stream(Idb_AccessibilityQuiescenceRequest(), using: executor)
    XCTAssertEqual(
      responses,
      [
        .with {
          $0.pid = 42
          $0.state = .with {
            $0.state = .busy
            $0.busySignals = [.animationsInactive, .runLoopIdle]
          }
        },
        .with {
          $0.pid = 42
          $0.touchesCompleted = .init()
        },
        .with {
          $0.pid = 42
          $0.state = .with { $0.state = .settling }
        },
        .with {
          $0.pid = 43
          $0.targetChanged = .init()
        },
        .with {
          $0.pid = 43
          $0.state = .with { $0.state = .quiet }
        },
        .with {
          $0.pid = 43
          $0.targetExited = .init()
        },
      ])
  }

  // A client cancelling the call cancels the handler's task, which must close the stream behind it.
  func testCancellingTheCallClosesTheStream() async throws {
    let forwarded = expectation(description: "the first event is forwarded")
    let closed = expectation(description: "the stream is closed")
    let executor = ScriptedQuiescenceExecutor(events: [.state(.settling, pid: 42)], holdsOpen: true) { closed.fulfill() }
    let call = Task {
      try await AccessibilityQuiescenceMethodHandler.stream(Idb_AccessibilityQuiescenceRequest(), using: executor) { _ in forwarded.fulfill() }
    }
    await fulfillment(of: [forwarded], timeout: 5)
    call.cancel()
    await fulfillment(of: [closed], timeout: 5)
    _ = await call.result
  }
}

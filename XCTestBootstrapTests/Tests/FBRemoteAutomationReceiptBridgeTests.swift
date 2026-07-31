/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTest
@testable import XCTestBootstrap

private enum BridgeTestError: Error { case injected }

/// A serial queue that backs the deadline timer. File-scoped and `Sendable` so it can be
/// captured into the `Task` the cancellation test spawns without capturing the test case.
private let bridgeTestQueue = DispatchQueue(label: "com.facebook.FBRemoteAutomation.bridgeTests")

/// Fires the completion synchronously with a preset value/error when the bridge registers it.
private final class ImmediateReceipt: NSObject, FBRemoteAutomationReceipt {
  private let value: Any?
  private let error: (any Error)?

  init(value: Any?, error: (any Error)?) {
    self.value = value
    self.error = error
  }

  func handleCompletion(_ completion: @escaping (Any?, (any Error)?) -> Void) {
    completion(value, error)
  }
}

/// Fires the completion twice, to prove the bridge resolves exactly once.
private final class DoubleFireReceipt: NSObject, FBRemoteAutomationReceipt {
  func handleCompletion(_ completion: @escaping (Any?, (any Error)?) -> Void) {
    completion("first" as NSString, nil)
    completion("second" as NSString, nil)
  }
}

/// Never fires, so the deadline timer or task cancellation is the only way out.
private final class SilentReceipt: NSObject, FBRemoteAutomationReceipt {
  func handleCompletion(_ completion: @escaping (Any?, (any Error)?) -> Void) {}
}

final class FBRemoteAutomationReceiptBridgeTests: XCTestCase {

  func testResolvesWithValueOnCompletion() async throws {
    let receipt = ImmediateReceipt(value: "payload" as NSString, error: nil)
    let result = try await awaitRemoteReceipt(receipt, operation: "op", deadline: 5, queue: bridgeTestQueue)
    XCTAssertEqual(result as? String, "payload", "A completed receipt must resolve with the delivered value.")
  }

  func testThrowsErrorOnCompletion() async {
    let receipt = ImmediateReceipt(value: nil, error: BridgeTestError.injected)
    do {
      _ = try await awaitRemoteReceipt(receipt, operation: "op", deadline: 5, queue: bridgeTestQueue)
      XCTFail("A receipt completing with an error must throw.")
    } catch is BridgeTestError {
      // expected
    } catch {
      XCTFail("Expected the receipt's own error to propagate, got \(error).")
    }
  }

  func testIgnoresSecondCompletion() async throws {
    let receipt = DoubleFireReceipt()
    let result = try await awaitRemoteReceipt(receipt, operation: "op", deadline: 5, queue: bridgeTestQueue)
    XCTAssertEqual(result as? String, "first", "A second completion must be ignored; only the first resume wins.")
  }

  func testMissingReceiptThrowsPayloadUnavailable() async {
    do {
      _ = try await awaitRemoteReceipt(nil, operation: "op", deadline: 5, queue: bridgeTestQueue)
      XCTFail("A nil receipt must throw payloadUnavailable.")
    } catch let error as FBRemoteInvocationError {
      guard case .payloadUnavailable = error else {
        return XCTFail("Expected payloadUnavailable, got \(error).")
      }
    } catch {
      XCTFail("Expected FBRemoteInvocationError, got \(error).")
    }
  }

  func testTimesOutWhenReceiptNeverCompletes() async {
    let receipt = SilentReceipt()
    do {
      _ = try await awaitRemoteReceipt(receipt, operation: "loadAccessibility", deadline: 0.1, queue: bridgeTestQueue)
      XCTFail("A receipt that never completes must hit the deadline.")
    } catch let error as FBRemoteInvocationError {
      guard case let .invocationTimedOut(operation, deadline) = error else {
        return XCTFail("Expected invocationTimedOut, got \(error).")
      }
      XCTAssertEqual(operation, "loadAccessibility")
      XCTAssertEqual(deadline, 0.1)
    } catch {
      XCTFail("Expected FBRemoteInvocationError, got \(error).")
    }
  }

  func testThrowsCancellationWhenTaskCancelled() async {
    let task = Task { () -> Any? in
      let receipt = SilentReceipt()
      return try await awaitRemoteReceipt(receipt, operation: "op", deadline: 30, queue: bridgeTestQueue)
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("A cancelled task must not resolve normally.")
    } catch is CancellationError {
      // expected
    } catch {
      XCTFail("Expected CancellationError, got \(error).")
    }
  }
}

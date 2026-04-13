/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import IDBCompanionUtilities

final class IDBCompanionUtilitiesTransientTests: XCTestCase {

  // MARK: - FBMutex Tests

  func testMutexSyncReturnsValue() {
    let mutex = FBMutex()
    let result = mutex.sync { 42 }
    XCTAssertEqual(result, 42)
  }

  func testMutexSyncThrows() {
    struct TestError: Error {}
    let mutex = FBMutex()
    XCTAssertThrowsError(try mutex.sync { throw TestError() })
  }

  func testMutexConcurrentAccess() {
    let mutex = FBMutex()
    var counter = 0
    DispatchQueue.concurrentPerform(iterations: 1000) { _ in
      mutex.sync { counter += 1 }
    }
    XCTAssertEqual(counter, 1000)
  }

  // MARK: - CodeLocation Tests

  func testCodeLocationDescriptionWithFunction() {
    let location = CodeLocation(function: "testFunc", file: "TestFile.swift", line: 10, column: 5)
    XCTAssertEqual(location.description, "Located at file: TestFile.swift, line: 10, column: 5, function: testFunc")
  }

  func testCodeLocationDescriptionWithoutFunction() {
    let location = CodeLocation(function: nil, file: "TestFile.swift", line: 10, column: 5)
    XCTAssertEqual(location.description, "Located at file: TestFile.swift, line: 10, column: 5")
  }

  // MARK: - TaskTimeoutError Tests

  func testTaskTimeoutErrorDescription() {
    let location = CodeLocation(function: "myFunc", file: "File.swift", line: 1, column: 1)
    let error = TaskTimeoutError(location: location)
    XCTAssertTrue(error.errorDescription?.contains("timeout") == true)
    XCTAssertTrue(error.errorDescription?.contains("File.swift") == true)
  }

  // MARK: - Task.select Tests

  func testSelectReturnsFirstCompletedTask() async {
    let fast = Task<Int, Never> { 1 }
    let slow = Task<Int, Never> {
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      return 2
    }
    let winner = await Task.select(fast, slow)
    let value = await winner.value
    XCTAssertEqual(value, 1)
    slow.cancel()
  }

  func testSelectWithSequence() async {
    let tasks = (0..<3).map { i in
      Task<Int, Never> {
        if i == 1 {
          return 99
        }
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        return i
      }
    }
    let winner = await Task.select(tasks)
    let value = await winner.value
    XCTAssertEqual(value, 99)
    for task in tasks { task.cancel() }
  }

  func testSelectCancellationCancelsTasks() async {
    let task1 = Task<Int, Never> {
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      return 1
    }
    let task2 = Task<Int, Never> {
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      return 2
    }

    let selectTask = Task<Task<Int, Never>, Never> {
      await Task.select(task1, task2)
    }

    // Give select time to register tasks, then cancel
    try? await Task.sleep(nanoseconds: 50_000_000)
    selectTask.cancel()

    // After cancellation, the underlying tasks should be cancelled
    try? await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertTrue(task1.isCancelled)
    XCTAssertTrue(task2.isCancelled)
  }

  // MARK: - Task.timeout Tests

  func testTimeoutSucceedsWhenJobCompletesInTime() async throws {
    let result = try await Task.timeout(nanoseconds: 1_000_000_000) {
      return 42
    }
    XCTAssertEqual(result, 42)
  }

  func testTimeoutThrowsWhenJobExceedsTimeout() async {
    do {
      _ = try await Task.timeout(nanoseconds: 10_000_000) {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return 1
      }
      XCTFail("Expected timeout error")
    } catch {
      XCTAssertTrue(error is TaskTimeoutError, "Expected TaskTimeoutError but got \(type(of: error))")
    }
  }

  func testTimeoutPropagatesJobError() async {
    struct JobError: Error {}
    do {
      _ = try await Task.timeout(nanoseconds: 1_000_000_000) {
        throw JobError()
      }
      XCTFail("Expected job error")
    } catch {
      XCTAssertTrue(error is JobError, "Expected JobError but got \(type(of: error))")
    }
  }

  // MARK: - FBTeardownContext Tests

  func testWithAutocleanupCallsCleanup() async throws {
    var cleaned = false
    try await FBTeardownContext.withAutocleanup {
      try FBTeardownContext.current.addCleanup {
        cleaned = true
      }
    }
    XCTAssertTrue(cleaned)
  }

  func testWithAutocleanupCallsCleanupInLIFOOrder() async throws {
    var order: [Int] = []
    try await FBTeardownContext.withAutocleanup {
      try FBTeardownContext.current.addCleanup {
        order.append(1)
      }
      try FBTeardownContext.current.addCleanup {
        order.append(2)
      }
      try FBTeardownContext.current.addCleanup {
        order.append(3)
      }
    }
    XCTAssertEqual(order, [3, 2, 1])
  }

  func testEmptyContextThrowsOnAddCleanup() async {
    let emptyContext = FBTeardownContext.current
    XCTAssertThrowsError(try emptyContext.addCleanup {}) { error in
      XCTAssertTrue(error is FBTeardownContextError)
      guard let contextError = error as? FBTeardownContextError else { return }
      switch contextError {
      case .emptyContext:
        break
      @unknown default:
        XCTFail("Unexpected error case")
      }
    }
  }

  func testEmptyContextThrowsOnPerformCleanup() async throws {
    let emptyContext = FBTeardownContext.current
    do {
      try await emptyContext.performCleanup()
      XCTFail("Expected emptyContext error")
    } catch {
      XCTAssertTrue(error is FBTeardownContextError)
    }
  }

  func testDoubleCleanupThrows() async throws {
    var cleanupCount = 0
    do {
      try await FBTeardownContext.withAutocleanup {
        let context = FBTeardownContext.current
        try context.addCleanup {
          cleanupCount += 1
        }
        // Manually perform cleanup before autocleanup triggers
        try await context.performCleanup()
      }
      XCTFail("Expected cleanupAlreadyPerformed error from autocleanup")
    } catch {
      XCTAssertTrue(error is FBTeardownContextError)
    }
    XCTAssertEqual(cleanupCount, 1)
  }

  func testAddCleanupAfterCleanupPerformedThrows() async throws {
    var context: FBTeardownContext?
    try await FBTeardownContext.withAutocleanup {
      context = FBTeardownContext.current
    }
    // Context cleanup already performed by withAutocleanup
    XCTAssertThrowsError(try context?.addCleanup {}) { error in
      XCTAssertTrue(error is FBTeardownContextError)
    }
  }

  func testWithAutocleanupReturnsValue() async throws {
    let result = try await FBTeardownContext.withAutocleanup {
      return 42
    }
    XCTAssertEqual(result, 42)
  }

  func testWithAutocleanupPropagatesError() async {
    struct TestError: Error {}
    do {
      _ = try await FBTeardownContext.withAutocleanup {
        throw TestError()
      }
      XCTFail("Expected error to propagate")
    } catch {
      XCTAssertTrue(error is TestError)
    }
  }
}

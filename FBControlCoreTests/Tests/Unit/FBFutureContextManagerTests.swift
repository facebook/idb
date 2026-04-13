/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import FBControlCore

final class FBFutureContextManagerTests: XCTestCase, FBFutureContextManagerDelegate {
  var queue: DispatchQueue!
  var prepareCalled: UInt = 0
  var teardownCalled: UInt = 0
  var contextPoolTimeout: NSNumber? = 0
  var failPrepare: Bool = false
  var resetFailPrepare: Bool = false
  var isContextSharable: Bool = false
  var logger: FBControlCoreLogger!

  override func setUp() {
    queue = DispatchQueue(label: "com.facebook.fbcontrolcore.tests.future_context")
    logger = FBControlCoreGlobalConfiguration.defaultLogger.withName("manager_test")
    isContextSharable = false
    contextPoolTimeout = 0
    prepareCalled = 0
    teardownCalled = 0
    failPrepare = false
    resetFailPrepare = false
  }

  var manager: FBFutureContextManager<NSNumber> {
    return FBFutureContextManager<NSNumber>(queue: queue, delegate: self, logger: logger)
  }

  func testSingleAquire() {
    let future =
      manager
      .utilize(withPurpose: "A Test")
      .onQueue(
        queue,
        pop: { result in
          return FBFuture<AnyObject>(result: NSNumber(value: 123))
        })

    let value = try? future.await(withTimeout: 1) as? NSNumber
    XCTAssertEqual(value, 123)

    XCTAssertEqual(prepareCalled, 1)
    XCTAssertEqual(teardownCalled, 1)
  }

  func testSequentialAquire() {
    let manager = self.manager

    let future0 =
      manager
      .utilize(withPurpose: "A Test")
      .onQueue(
        queue,
        pop: { result in
          return FBFuture<AnyObject>(result: NSNumber(value: 0))
        })

    var value = try? future0.await(withTimeout: 1) as? NSNumber
    XCTAssertEqual(value, 0)

    XCTAssertEqual(prepareCalled, 1)
    XCTAssertEqual(teardownCalled, 1)

    let future1 =
      manager
      .utilize(withPurpose: "A Test")
      .onQueue(
        queue,
        pop: { result in
          return FBFuture<AnyObject>(result: NSNumber(value: 1))
        })
    value = try? future1.await(withTimeout: 1) as? NSNumber
    XCTAssertEqual(value, 1)

    XCTAssertEqual(prepareCalled, 2)
    XCTAssertEqual(teardownCalled, 2)
  }

  func testConcurrentAquireOnlyPreparesOnce() {
    let manager = self.manager
    let queue = self.queue!
    let logger = self.logger!
    let concurrent = DispatchQueue(label: "com.facebook.fbcontrolcore.tests.future_context.concurrent", attributes: .concurrent)
    let future0 = FBMutableFuture<AnyObject>()
    let future1 = FBMutableFuture<AnyObject>()
    let future2 = FBMutableFuture<AnyObject>()

    let block0: @convention(block) () -> Void = {
      let inner =
        manager
        .utilize(withPurpose: "Test 0")
        .onQueue(
          queue,
          pop: { result in
            logger.log("Test 0 In Use")
            return FBFuture<AnyObject>(result: NSNumber(value: 0))
          })
      (future0 as! FBMutableFuture).resolve(from: inner)
    }
    let block1: @convention(block) () -> Void = {
      let inner =
        manager
        .utilize(withPurpose: "Test 1")
        .onQueue(
          queue,
          pop: { result in
            logger.log("Test 1 In Use")
            return FBFuture<AnyObject>(result: NSNumber(value: 1))
          })
      (future1 as! FBMutableFuture).resolve(from: inner)
    }
    let block2: @convention(block) () -> Void = {
      let inner =
        manager
        .utilize(withPurpose: "Test 2")
        .onQueue(
          queue,
          pop: { result in
            logger.log("Test 2 In Use")
            return FBFuture<AnyObject>(result: NSNumber(value: 2))
          })
      (future2 as! FBMutableFuture).resolve(from: inner)
    }

    concurrent.async(execute: block0)
    concurrent.async(execute: block1)
    concurrent.async(execute: block2)

    let value = try? FBFuture<AnyObject>.combine([future0, future1, future2]).await(withTimeout: 1) as NSArray?
    XCTAssertNotNil(value)
    XCTAssertEqual(value as? NSArray, [0, 1, 2] as NSArray)

    XCTAssertEqual(prepareCalled, 1)
    XCTAssertEqual(teardownCalled, 1)
  }

  func testConcurrentAquireWithSharableResource() {
    let manager = self.manager
    let queue = self.queue!
    let logger = self.logger!
    isContextSharable = true
    let concurrent = DispatchQueue(label: "com.facebook.fbcontrolcore.tests.future_context.concurrent", attributes: .concurrent)
    let future0 = FBMutableFuture<AnyObject>()
    let future1 = FBMutableFuture<AnyObject>()
    let future2 = FBMutableFuture<AnyObject>()

    let block0: @convention(block) () -> Void = {
      let inner =
        manager
        .utilize(withPurpose: "Test 0")
        .onQueue(
          queue,
          pop: { result in
            logger.log("Test 0 In Use")
            return FBFuture<AnyObject>(result: NSNumber(value: 0))
          })
      (future0 as! FBMutableFuture).resolve(from: inner)
    }
    let block1: @convention(block) () -> Void = {
      let inner =
        manager
        .utilize(withPurpose: "Test 1")
        .onQueue(
          queue,
          pop: { result in
            logger.log("Test 1 In Use")
            return FBFuture<AnyObject>(result: NSNumber(value: 1))
          })
      (future1 as! FBMutableFuture).resolve(from: inner)
    }
    let block2: @convention(block) () -> Void = {
      let inner =
        manager
        .utilize(withPurpose: "Test 2")
        .onQueue(
          queue,
          pop: { result in
            logger.log("Test 2 In Use")
            return FBFuture<AnyObject>(result: NSNumber(value: 2))
          })
      (future2 as! FBMutableFuture).resolve(from: inner)
    }

    concurrent.async(execute: block0)
    concurrent.async(execute: block1)
    concurrent.async(execute: block2)

    let value = try? FBFuture<AnyObject>.combine([future0, future1, future2]).await(withTimeout: 1) as NSArray?
    XCTAssertNotNil(value)
    XCTAssertEqual(value as? NSArray, [0, 1, 2] as NSArray)

    XCTAssertEqual(prepareCalled, 1)
    XCTAssertEqual(teardownCalled, 1)
  }

  func testFailInPrepare() {
    let manager = self.manager
    failPrepare = true
    let future0 =
      manager
      .utilize(withPurpose: "A Test")
      .onQueue(
        queue,
        pop: { result in
          return FBFuture<AnyObject>(result: NSNumber(value: 0))
        })

    do {
      _ = try future0.await(withTimeout: 1)
      XCTFail("Expected error")
    } catch {
      // Expected error
    }

    XCTAssertEqual(prepareCalled, 1)
    XCTAssertEqual(teardownCalled, 0)

    failPrepare = false
    let future1 =
      manager
      .utilize(withPurpose: "A Test")
      .onQueue(
        queue,
        pop: { result in
          return FBFuture<AnyObject>(result: NSNumber(value: 1))
        })
    let value = try? future1.await(withTimeout: 1) as? NSNumber
    XCTAssertEqual(value, 1)

    XCTAssertEqual(prepareCalled, 2)
    XCTAssertEqual(teardownCalled, 1)
  }

  func testConcurrentAquireWithOneFailInPrepare() {
    let manager = self.manager
    let queue = self.queue!
    let concurrent = DispatchQueue(label: "com.facebook.fbcontrolcore.tests.future_context.concurrent", attributes: .concurrent)
    let future0 = FBMutableFuture<AnyObject>()
    let future1 = FBMutableFuture<AnyObject>()
    let future2 = FBMutableFuture<AnyObject>()

    failPrepare = true
    resetFailPrepare = true

    let block0: @convention(block) () -> Void = {
      let inner =
        manager
        .utilize(withPurpose: "A Test 1")
        .onQueue(
          queue,
          pop: { result in
            return FBFuture<AnyObject>(result: NSNumber(value: 0))
          })
      (future0 as! FBMutableFuture).resolve(from: inner)
    }
    let block1: @convention(block) () -> Void = {
      let inner =
        manager
        .utilize(withPurpose: "A Test 2")
        .onQueue(
          queue,
          pop: { result in
            return FBFuture<AnyObject>(result: NSNumber(value: 1))
          })
      (future1 as! FBMutableFuture).resolve(from: inner)
    }
    let block2: @convention(block) () -> Void = {
      let inner =
        manager
        .utilize(withPurpose: "A Test 3")
        .onQueue(
          queue,
          pop: { result in
            return FBFuture<AnyObject>(result: NSNumber(value: 2))
          })
      (future2 as! FBMutableFuture).resolve(from: inner)
    }

    concurrent.async(execute: block0)
    concurrent.async(execute: block1)
    concurrent.async(execute: block2)

    var values: [NSNumber] = []
    var errors: [Error] = []

    for future in [future0, future1, future2] {
      do {
        if let value = try future.await(withTimeout: 1) as? NSNumber {
          values.append(value)
        }
      } catch {
        errors.append(error)
      }
    }

    XCTAssertEqual(values.count, 2)
    XCTAssertEqual(errors.count, 1)

    XCTAssertEqual(prepareCalled, 2)
    XCTAssertEqual(teardownCalled, 1)
  }

  func testImmediateAquireAndRelease() throws {
    let manager = self.manager

    let context = try manager.utilizeNow(withPurpose: "A Test")
    XCTAssertEqual(context as? NSNumber, 0)

    try manager.returnNow(withPurpose: "A Test")
  }

  // MARK: - FBFutureContextManagerDelegate

  var contextName: String {
    return "A Test"
  }

  func prepare(_ logger: FBControlCoreLogger) -> FBFuture<AnyObject> {
    prepareCalled += 1
    if failPrepare {
      if resetFailPrepare {
        failPrepare = false
      }
      return FBControlCoreError.describe("Error in prepare").failFuture()
    } else {
      return FBFuture<AnyObject>(result: NSNumber(value: 0))
    }
  }

  func teardown(_ context: Any, logger: FBControlCoreLogger) -> FBFuture<NSNull> {
    teardownCalled += 1
    return FBFuture<NSNull>.empty()
  }
}

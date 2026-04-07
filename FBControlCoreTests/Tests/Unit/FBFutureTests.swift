/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import FBControlCore

/// Helper to call the NS_SWIFT_UNAVAILABLE `futureWithFutures:` method from Swift tests.
private func composeFutures(_ futures: [FBFuture<AnyObject>]) -> FBFuture<NSArray> {
  let selector = NSSelectorFromString("futureWithFutures:")
  // swiftlint:disable:next force_cast
  let result = (FBFuture<NSArray>.self as AnyObject).perform(selector, with: futures)!
  // swiftlint:disable:next force_cast
  return result.takeUnretainedValue() as! FBFuture<NSArray>
}

final class FBFutureTests: XCTestCase {

  var queue: DispatchQueue!

  override func setUp() {
    queue = DispatchQueue(label: "com.facebook.fbcontrolcore.tests.future")
  }

  func testResolvesSynchronouslyWithObject() {
    assertSynchronousResolution(
      withBlock: { future in
        future.resolve(withResult: NSNumber(value: true))
      }, expectedState: .done, expectedResult: NSNumber(value: true), expectedError: nil)
  }

  func testResolvesAsynchronouslyWithObject() {
    waitForAsynchronousResolution(
      withBlock: { future in
        future.resolve(withResult: NSNumber(value: true))
      }, expectedState: .done, expectationKeyPath: "result", expectationValue: NSNumber(value: true))
  }

  func testResolvesSynchronouslyWithError() {
    let error = NSError(domain: "foo", code: 2, userInfo: nil)
    assertSynchronousResolution(
      withBlock: { future in
        future.perform(NSSelectorFromString("resolveWithError:"), with: error)
      }, expectedState: .failed, expectedResult: nil, expectedError: error)
  }

  func testResolvesAsynchronouslyWithError() {
    let error = NSError(domain: "foo", code: 2, userInfo: nil)
    waitForAsynchronousResolution(
      withBlock: { future in
        future.perform(NSSelectorFromString("resolveWithError:"), with: error)
      }, expectedState: .failed, expectationKeyPath: "error", expectationValue: error)
  }

  func testEarlyCancellation() {
    assertSynchronousResolution(
      withBlock: { future in
        future.cancel()
      }, expectedState: .cancelled, expectedResult: nil, expectedError: nil)
  }

  func testAsynchronousCancellation() {
    waitForAsynchronousResolution(
      withBlock: { future in
        future.cancel()
      }, expectedState: .cancelled, expectationKeyPath: nil, expectationValue: nil)
  }

  func testDiscardsAllResolutionsAfterTheFirst() {
    let future = FBMutableFuture<NSNumber>()

    future.resolve(withResult: NSNumber(value: true))

    XCTAssertEqual(future.state, .done)
    XCTAssertEqual(future.hasCompleted, true)
    XCTAssertEqual(future.result as? NSNumber, NSNumber(value: true))
    XCTAssertNil(future.error)

    future.perform(NSSelectorFromString("resolveWithError:"), with: NSError(domain: "foo", code: 0, userInfo: nil))

    XCTAssertEqual(future.state, .done)
    XCTAssertEqual(future.hasCompleted, true)
    XCTAssertEqual(future.result as? NSNumber, NSNumber(value: true))
    XCTAssertNil(future.error)
  }

  func testCallbacks() {
    let future = FBMutableFuture<NSNumber>()
    var handlerCount: UInt = 0
    future.onQueue(
      queue,
      notifyOfCompletion: { _ in
        objc_sync_enter(self)
        handlerCount += 1
        objc_sync_exit(self)
      })
    future.onQueue(
      queue,
      notifyOfCompletion: { _ in
        objc_sync_enter(self)
        handlerCount += 1
        objc_sync_exit(self)
      })
    future.onQueue(
      queue,
      notifyOfCompletion: { _ in
        objc_sync_enter(self)
        handlerCount += 1
        objc_sync_exit(self)
      })
    queue.async {
      future.resolve(withResult: NSNumber(value: true))
    }
    let predicate = NSPredicate { _, _ in
      objc_sync_enter(self)
      let result = handlerCount == 3
      objc_sync_exit(self)
      return result
    }
    let expectation = self.expectation(for: predicate, evaluatedWith: self)
    wait(for: [expectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testDoActionCallback() {
    let actionExpectation = XCTestExpectation(description: "Action Callback called")
    let completionExpectation = XCTestExpectation(description: "Completion called")
    var actionCalled = false

    FBFuture<AnyObject>(result: NSNumber(value: true))
      .onQueue(
        queue,
        doOnResolved: { value in
          XCTAssertEqual(value as? NSNumber, NSNumber(value: true))
          actionCalled = true
          actionExpectation.fulfill()
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.result as? NSNumber, NSNumber(value: true))
          XCTAssertTrue(actionCalled)
          completionExpectation.fulfill()
        })

    wait(for: [actionExpectation, completionExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testCompositeSuccess() {
    let expectation = XCTestExpectation(description: "Composite Callback is called")

    let future1 = FBMutableFuture<NSNumber>()
    let future2 = FBMutableFuture<NSNumber>()
    let future3 = FBMutableFuture<NSNumber>()
    let compositeFuture = composeFutures([future1, future2, future3])
      .onQueue(
        DispatchQueue.global(qos: .userInitiated),
        notifyOfCompletion: { _ in
          expectation.fulfill()
        })

    queue.async {
      future1.resolve(withResult: NSNumber(value: true))
    }
    queue.async {
      future2.resolve(withResult: NSNumber(value: false))
    }
    queue.async {
      future3.resolve(withResult: NSNumber(value: 10))
    }

    let expected = [NSNumber(value: true), NSNumber(value: false), NSNumber(value: 10)] as NSArray
    wait(for: [expectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertEqual(compositeFuture.state, .done)
    XCTAssertEqual(compositeFuture.result, expected)
  }

  func testCompositeImmediateValue() {
    let compositeFuture = composeFutures([
      FBFuture(result: NSNumber(value: 0)),
      FBFuture(result: NSNumber(value: 1)),
      FBFuture(result: NSNumber(value: 2)),
    ])

    XCTAssertEqual(compositeFuture.state, .done)
    XCTAssertEqual(compositeFuture.result, [NSNumber(value: 0), NSNumber(value: 1), NSNumber(value: 2)] as NSArray)
  }

  func testCompositeEmpty() {
    let compositeFuture = composeFutures([])

    XCTAssertEqual(compositeFuture.state, .done)
    XCTAssertEqual(compositeFuture.result, [] as NSArray)
  }

  func testCompositeFailure() {
    let error = NSError(domain: "foo", code: 2, userInfo: nil)
    let pending = FBMutableFuture<NSNumber>()
    let compositeFuture = composeFutures([
      FBFuture(result: NSNumber(value: 0)),
      pending,
      FBFuture(error: error),
    ])

    XCTAssertEqual(compositeFuture.state, .failed)
    XCTAssertEqual(compositeFuture.error as NSError?, error)
    XCTAssertEqual(pending.state, .running)
  }

  func testCompositeCancellation() {
    let pending = FBMutableFuture<NSNumber>()
    let cancelled = FBMutableFuture<NSNumber>()
    cancelled.cancel()
    let compositeFuture = composeFutures([
      FBFuture(result: NSNumber(value: 0)),
      pending,
      cancelled,
    ])

    XCTAssertEqual(compositeFuture.state, .cancelled)
    XCTAssertEqual(pending.state, .running)
  }

  func testFmappedSuccess() {
    let step1 = XCTestExpectation(description: "fmap 1 is called")
    let step2 = XCTestExpectation(description: "fmap 2 is called")
    let step3 = XCTestExpectation(description: "Completion is called")

    let baseFuture = FBMutableFuture<NSNumber>()
    let chainFuture =
      baseFuture
      .onQueue(
        queue,
        fmap: { value in
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          step1.fulfill()
          return FBFuture<AnyObject>(result: NSNumber(value: 2))
        }
      )
      .onQueue(
        queue,
        fmap: { value in
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 2))
          step2.fulfill()
          return FBFuture<AnyObject>(result: NSNumber(value: 3))
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.result as? NSNumber, NSNumber(value: 3))
          step3.fulfill()
        })
    queue.async {
      baseFuture.resolve(withResult: NSNumber(value: 1))
    }

    wait(for: [step1, step2, step3], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertEqual(chainFuture.state, .done)
    XCTAssertEqual(chainFuture.result as? NSNumber, NSNumber(value: 3))
  }

  func testTerminateFmapOnError() {
    let step1 = XCTestExpectation(description: "fmap 1 is called")
    let step2 = XCTestExpectation(description: "fmap 2 is called")
    let step3 = XCTestExpectation(description: "Completion is called")
    let error = NSError(domain: "foo", code: 2, userInfo: nil)

    let baseFuture = FBMutableFuture<NSNumber>()
    let chainFuture =
      baseFuture
      .onQueue(
        queue,
        fmap: { value in
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          step1.fulfill()
          return FBFuture<AnyObject>(result: NSNumber(value: 2))
        }
      )
      .onQueue(
        queue,
        fmap: { value in
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 2))
          step2.fulfill()
          return FBFuture<AnyObject>(error: error)
        }
      )
      .onQueue(
        queue,
        fmap: { _ -> FBFuture<AnyObject> in
          XCTFail("Chained block should not be called after failure")
          return FBFuture<AnyObject>(error: error)
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.error as NSError?, error)
          step3.fulfill()
        })
    queue.async {
      baseFuture.resolve(withResult: NSNumber(value: 1))
    }

    wait(for: [step1, step2, step3], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertEqual(chainFuture.state, .failed)
    XCTAssertEqual(chainFuture.error as NSError?, error)
  }

  func testAsyncTimeout() {
    let future = FBMutableFuture<NSNumber>()

    do {
      let value = try future.await(withTimeout: 1)
      XCTAssertNil(value)
      XCTFail("Expected error to be thrown")
    } catch {
      XCTAssertNotNil(error)
    }
  }

  func testAsyncResolution() {
    let future = FBMutableFuture<NSNumber>()
    queue.async {
      future.resolve(withResult: NSNumber(value: true))
    }

    do {
      let value = try future.await(withTimeout: 1)
      XCTAssertEqual(value as? NSNumber, NSNumber(value: true))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testAsyncErrorPropogation() {
    let expected = NSError(domain: "foo", code: 0, userInfo: nil)
    let future = FBMutableFuture<NSNumber>()
    queue.async {
      future.perform(NSSelectorFromString("resolveWithError:"), with: expected)
    }

    do {
      let value = try future.await(withTimeout: 1)
      XCTAssertNil(value)
      XCTFail("Expected error to be thrown")
    } catch {
      XCTAssertEqual(error as NSError, expected)
    }
  }

  func testAsyncCancellation() {
    let future = FBMutableFuture<NSNumber>()
    queue.async {
      future.cancel()
    }

    do {
      let value = try future.await(withTimeout: 1)
      XCTAssertNil(value)
      XCTFail("Expected error to be thrown")
    } catch {
      XCTAssertNotNil(error.localizedDescription)
    }
  }

  func testChainValueThenError() {
    let step1 = XCTestExpectation(description: "chain1 is called")
    let step2 = XCTestExpectation(description: "chain2 is called")
    let step3 = XCTestExpectation(description: "chain3 is called")
    let step4 = XCTestExpectation(description: "Completion is called")
    let error = NSError(domain: "foo", code: 2, userInfo: nil)

    let baseFuture = FBMutableFuture<NSNumber>()
    let chainFuture =
      baseFuture
      .onQueue(
        queue,
        chain: { future in
          XCTAssertEqual(future.result as? NSNumber, NSNumber(value: 1))
          step1.fulfill()
          return FBFuture<AnyObject>(result: NSNumber(value: 2))
        }
      )
      .onQueue(
        queue,
        chain: { future in
          XCTAssertEqual(future.result as? NSNumber, NSNumber(value: 2))
          step2.fulfill()
          return FBFuture<AnyObject>(error: error)
        }
      )
      .onQueue(
        queue,
        chain: { future -> FBFuture<AnyObject> in
          XCTAssertEqual(future.error as NSError?, error)
          step3.fulfill()
          return FBFuture<AnyObject>(result: NSNumber(value: 4))
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.result as? NSNumber, NSNumber(value: 4))
          step4.fulfill()
        })
    queue.async {
      baseFuture.resolve(withResult: NSNumber(value: 1))
    }

    wait(for: [step1, step2, step3, step4], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertEqual(chainFuture.state, .done)
    XCTAssertEqual(chainFuture.result as? NSNumber, NSNumber(value: 4))
  }

  func testChainingToHandleCancellation() {
    let completion = XCTestExpectation(description: "completion is called")
    let chained = XCTestExpectation(description: "chain is called")
    let remapped = XCTestExpectation(description: "fmap on handling cancellation")

    let baseFuture = FBMutableFuture<NSNumber>()
    let chainFuture =
      baseFuture
      .onQueue(
        queue,
        chain: { _ in
          chained.fulfill()
          return FBFuture<AnyObject>(result: NSNumber(value: 2))
        }
      )
      .onQueue(
        queue,
        fmap: { _ in
          remapped.fulfill()
          return FBFuture<AnyObject>(result: NSNumber(value: 3))
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.state, .done)
          XCTAssertEqual(future.result as? NSNumber, NSNumber(value: 3))
          completion.fulfill()
        })
    queue.async {
      baseFuture.cancel()
    }

    wait(for: [completion, chained, remapped], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertEqual(chainFuture.state, .done)
    XCTAssertEqual(chainFuture.result as? NSNumber, NSNumber(value: 3))
  }

  func testUnhandledCancellationWillPropogate() {
    let firstChain = XCTestExpectation(description: "first chain is called")
    let secondChain = XCTestExpectation(description: "second chain is called")
    let completion = XCTestExpectation(description: "completion is called")

    let baseFuture = FBMutableFuture<NSNumber>()
    let chainFuture =
      baseFuture
      .onQueue(
        queue,
        chain: { _ in
          firstChain.fulfill()
          let future = FBMutableFuture<NSNumber>()
          future.cancel()
          return future
        }
      )
      .onQueue(
        queue,
        chain: { future in
          XCTAssertEqual(future.state, .cancelled)
          secondChain.fulfill()
          return future
        }
      )
      .onQueue(
        queue,
        fmap: { _ in
          XCTFail("fmap should not be called")
          return FBMutableFuture<NSNumber>()
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.state, .cancelled)
          completion.fulfill()
        })
    queue.async {
      baseFuture.resolve(withResult: NSNumber(value: 0))
    }

    wait(for: [firstChain, secondChain, completion], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertEqual(chainFuture.state, .cancelled)
  }

  func testRaceSuccessFutures() {
    let completion = XCTestExpectation(description: "Completion is called")
    let late1Cancelled = XCTestExpectation(description: "Cancellation of late future 1")
    let late2Cancelled = XCTestExpectation(description: "Cancellation of late future 2")

    let lateFuture1 = FBMutableFuture<NSNumber>()
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.state, .cancelled)
          late1Cancelled.fulfill()
        })
    let lateFuture2 = FBMutableFuture<NSNumber>()
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.state, .cancelled)
          late2Cancelled.fulfill()
        })
    let raceFuture = FBFuture<AnyObject>(race: [
      lateFuture1,
      FBFuture<AnyObject>(result: NSNumber(value: 1)),
      lateFuture2,
    ])
    .onQueue(
      queue,
      notifyOfCompletion: { future in
        XCTAssertEqual(future.state, .done)
        XCTAssertEqual(future.result as? NSNumber, NSNumber(value: 1))
        completion.fulfill()
      })

    wait(for: [completion, late1Cancelled, late2Cancelled], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertEqual(raceFuture.state, .done)
    XCTAssertEqual(raceFuture.result as? NSNumber, NSNumber(value: 1))
    XCTAssertEqual(lateFuture1.state, .cancelled)
    XCTAssertEqual(lateFuture2.state, .cancelled)
  }

  func testRaceFailFutures() {
    let completion = XCTestExpectation(description: "Completion is called")
    let late1Cancelled = XCTestExpectation(description: "Cancellation of late future 1")
    let late2Cancelled = XCTestExpectation(description: "Cancellation of late future 2")

    let lateFuture1 = FBMutableFuture<NSNumber>()
      .onQueue(
        queue,
        respondToCancellation: {
          late1Cancelled.fulfill()
          return FBFuture<NSNull>.empty()
        })
    let lateFuture2 = FBMutableFuture<NSNumber>()
      .onQueue(
        queue,
        respondToCancellation: {
          late2Cancelled.fulfill()
          return FBFuture<NSNull>.empty()
        })

    let error = NSError(domain: "Future with error", code: 2, userInfo: nil)
    let raceFuture = FBFuture<AnyObject>(race: [
      lateFuture1,
      FBFuture<AnyObject>(error: error),
      lateFuture2,
    ])
    .onQueue(
      queue,
      notifyOfCompletion: { future in
        XCTAssertEqual(future.state, .failed)
        XCTAssertEqual(future.error as NSError?, error)
        completion.fulfill()
      })

    wait(for: [completion, late1Cancelled, late2Cancelled], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertEqual(raceFuture.state, .failed)
    XCTAssertEqual(raceFuture.error as NSError?, error)
    XCTAssertEqual(lateFuture1.state, .cancelled)
    XCTAssertEqual(lateFuture2.state, .cancelled)
  }

  func testAllCancelledPropogates() {
    let completion = XCTestExpectation(description: "Completion is called")
    let cancel1Called = XCTestExpectation(description: "Cancellation of late future 1")
    let cancel2Called = XCTestExpectation(description: "Cancellation of late future 2")
    let cancel3Called = XCTestExpectation(description: "Cancellation of late future 3")

    let cancelFuture1 = FBMutableFuture<NSNumber>()
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.state, .cancelled)
          cancel1Called.fulfill()
        })
    let cancelFuture2 = FBMutableFuture<NSNumber>()
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.state, .cancelled)
          cancel2Called.fulfill()
        })
    let cancelFuture3 = FBMutableFuture<NSNumber>()
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.state, .cancelled)
          cancel3Called.fulfill()
        })

    let raceFuture = FBFuture<AnyObject>(race: [
      cancelFuture1,
      cancelFuture2,
      cancelFuture3,
    ])
    .onQueue(
      queue,
      notifyOfCompletion: { future in
        XCTAssertEqual(future.state, .cancelled)
        completion.fulfill()
      })

    queue.async {
      cancelFuture1.cancel()
    }
    queue.async {
      cancelFuture2.cancel()
    }
    queue.async {
      cancelFuture3.cancel()
    }

    wait(for: [completion, cancel1Called, cancel2Called, cancel3Called], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertEqual(raceFuture.state, .cancelled)
    XCTAssertEqual(cancelFuture1.state, .cancelled)
    XCTAssertEqual(cancelFuture2.state, .cancelled)
    XCTAssertEqual(cancelFuture3.state, .cancelled)
  }

  func testImmediateValue() {
    let error = NSError(domain: "foo", code: 0, userInfo: nil)
    let successFuture = FBFuture<AnyObject>(result: NSNumber(value: 1))
    let errorFuture = FBFuture<AnyObject>(error: error)

    XCTAssertEqual(successFuture.state, .done)
    XCTAssertEqual(successFuture.result as? NSNumber, NSNumber(value: 1))
    XCTAssertEqual(errorFuture.state, .failed)
    XCTAssertEqual(errorFuture.error as NSError?, error)
  }

  func testImmedateValueInRaceBasedOnOrdering() {
    let error = NSError(domain: "foo", code: 0, userInfo: nil)
    var raceFuture = FBFuture<AnyObject>(race: [
      FBFuture<AnyObject>(result: NSNumber(value: 1)),
      FBFuture<AnyObject>(error: error),
      FBMutableFuture<NSNumber>(),
    ])
    XCTAssertEqual(raceFuture.state, .done)
    XCTAssertEqual(raceFuture.result as? NSNumber, NSNumber(value: 1))

    raceFuture = FBFuture<AnyObject>(race: [
      FBFuture<AnyObject>(error: error),
      FBMutableFuture<NSNumber>(),
      FBFuture<AnyObject>(result: NSNumber(value: 2)),
    ])
    XCTAssertEqual(raceFuture.state, .failed)
    XCTAssertEqual(raceFuture.error as NSError?, error)
  }

  func testAsyncConstructor() {
    let resultCalled = XCTestExpectation(description: "Result Future")
    let errorCalled = XCTestExpectation(description: "Error Future")
    let cancelCalled = XCTestExpectation(description: "Cancel Future")

    let error = NSError(domain: "foo", code: 0, userInfo: nil)
    let resultFuture = FBFuture<AnyObject>.onQueue(
      queue,
      resolve: {
        resultCalled.fulfill()
        return FBFuture<AnyObject>(result: NSNumber(value: 0))
      })
    let errorFuture = FBFuture<AnyObject>.onQueue(
      queue,
      resolve: {
        errorCalled.fulfill()
        return FBFuture<AnyObject>(error: error)
      })
    let cancelFuture = FBFuture<AnyObject>.onQueue(
      queue,
      resolve: {
        let future = FBMutableFuture<NSNumber>()
        future.cancel()
        cancelCalled.fulfill()
        return future
      })

    wait(for: [resultCalled, errorCalled, cancelCalled], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertEqual(resultFuture.state, .done)
    XCTAssertEqual(errorFuture.state, .failed)
    XCTAssertEqual(cancelFuture.state, .cancelled)
  }

  func testTimedOutIn() {
    let future = FBMutableFuture<NSNumber>()
      .onQueue(
        queue, timeout: 0.1,
        handler: {
          return FBFuture<AnyObject>(error: NSError(domain: "FBFutureTests", code: 0, userInfo: [NSLocalizedDescriptionKey: "Some Condition"]))
        })

    XCTAssertFalse(future.hasCompleted)
    XCTAssertEqual(future.state, .running)
    XCTAssertNil(future.result)
    XCTAssertNil(future.error)

    wait(
      for: [
        keyValueObservingExpectation(for: future, keyPath: "hasCompleted", expectedValue: true),
        keyValueObservingExpectation(for: future, keyPath: "state", expectedValue: FBFutureState.failed.rawValue as NSNumber),
      ], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testResolveWhen() {
    var resolveCount = 2
    let future = FBFuture<NSNull>.onQueue(
      queue,
      resolveWhen: {
        resolveCount -= 1
        return resolveCount == 0
      })

    wait(
      for: [
        keyValueObservingExpectation(for: future, keyPath: "hasCompleted", expectedValue: true),
        keyValueObservingExpectation(for: future, keyPath: "result", expectedValue: NSNull()),
        keyValueObservingExpectation(for: future, keyPath: "state", expectedValue: FBFutureState.done.rawValue as NSNumber),
      ], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testResolveOrFailWhenFailureCase() {
    var resolveCount = 2
    let expectedError = NSError(domain: "user error", code: 1, userInfo: nil)
    let future = FBFuture<NSNull>.onQueue(
      queue,
      resolveOrFailWhen: { error in
        resolveCount -= 1
        if resolveCount == 0 {
          error?.pointee = expectedError
          return .failed
        }
        return .continue
      })

    wait(
      for: [
        keyValueObservingExpectation(for: future, keyPath: "hasCompleted", expectedValue: true),
        keyValueObservingExpectation(for: future, keyPath: "error", expectedValue: expectedError),
        keyValueObservingExpectation(for: future, keyPath: "state", expectedValue: FBFutureState.failed.rawValue as NSNumber),
      ], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testResolveOrFailWhenSuccessCase() {
    var resolveCount = 2
    let future = FBFuture<NSNull>.onQueue(
      queue,
      resolveOrFailWhen: { _ in
        resolveCount -= 1
        if resolveCount == 0 {
          return .finished
        }
        return .continue
      })

    wait(
      for: [
        keyValueObservingExpectation(for: future, keyPath: "hasCompleted", expectedValue: true),
        keyValueObservingExpectation(for: future, keyPath: "result", expectedValue: NSNull()),
        keyValueObservingExpectation(for: future, keyPath: "state", expectedValue: FBFutureState.done.rawValue as NSNumber),
      ], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testChainReplaceSuccessful() {
    let replacement = FBMutableFuture<NSNumber>()
    let future = FBFuture<AnyObject>(result: NSNumber(value: false)).chainReplace(replacement).delay(0.1)
    queue.async {
      replacement.resolve(withResult: NSNumber(value: true))
    }

    wait(
      for: [
        keyValueObservingExpectation(for: future, keyPath: "result", expectedValue: NSNumber(value: true)),
        keyValueObservingExpectation(for: future, keyPath: "state", expectedValue: FBFutureState.done.rawValue as NSNumber),
      ], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testChainReplaceFailing() {
    let error = NSError(domain: "foo", code: 0, userInfo: nil)
    let replacement = FBMutableFuture<NSNumber>()
    let future = FBFuture<AnyObject>(error: error).chainReplace(replacement).delay(0.1)
    queue.async {
      replacement.resolve(withResult: NSNumber(value: true))
    }

    wait(
      for: [
        keyValueObservingExpectation(for: future, keyPath: "result", expectedValue: NSNumber(value: true)),
        keyValueObservingExpectation(for: future, keyPath: "state", expectedValue: FBFutureState.done.rawValue as NSNumber),
      ], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testRemappedTimeout() {
    let future = FBFuture<AnyObject>(result: NSNumber(value: 0))
      .delay(10)
      .onQueue(
        queue, timeout: 0.1,
        handler: {
          return FBFuture<AnyObject>(result: NSNumber(value: 1))
        })

    wait(
      for: [
        keyValueObservingExpectation(for: future, keyPath: "hasCompleted", expectedValue: true),
        keyValueObservingExpectation(for: future, keyPath: "result", expectedValue: NSNumber(value: 1)),
        keyValueObservingExpectation(for: future, keyPath: "state", expectedValue: FBFutureState.done.rawValue as NSNumber),
      ], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testFallback() {
    let error = NSError(domain: "foo", code: 0, userInfo: nil)
    let future = FBFuture<AnyObject>(error: error).fallback(NSNumber(value: true)).delay(0.1)

    wait(
      for: [
        keyValueObservingExpectation(for: future, keyPath: "result", expectedValue: NSNumber(value: true)),
        keyValueObservingExpectation(for: future, keyPath: "state", expectedValue: FBFutureState.done.rawValue as NSNumber),
      ], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testRepeatedResolution() {
    let completionCalled = XCTestExpectation(description: "Resolved outer Completion")
    let error = NSError(domain: "foo", code: 2, userInfo: nil)
    let futures: [FBFuture<AnyObject>] = [
      FBFuture<AnyObject>(error: error),
      FBFuture<AnyObject>(error: error),
      FBFuture<AnyObject>(error: error),
      FBFuture<AnyObject>(result: NSNumber(value: true)),
    ]
    var index = 0
    let future = FBFuture<AnyObject>.onQueue(
      queue,
      resolveUntil: {
        let inner = futures[index]
        index += 1
        return inner
      })
    future.onQueue(
      queue,
      notifyOfCompletion: { inner in
        completionCalled.fulfill()
        XCTAssertEqual(inner.result as? NSNumber, NSNumber(value: true))
      })

    wait(for: [completionCalled], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertEqual(future.state, .done)
    XCTAssertEqual(future.result as? NSNumber, NSNumber(value: true))
  }

  func testCancelledResolution() {
    let completionCalled = XCTestExpectation(description: "Resolved outer Completion")
    let error = NSError(domain: "foo", code: 2, userInfo: nil)
    let cancelledFuture: FBFuture<AnyObject> = FBMutableFuture<AnyObject>()
    cancelledFuture.cancel()
    let futures: [FBFuture<AnyObject>] = [
      FBFuture<AnyObject>(error: error),
      cancelledFuture,
      FBFuture<AnyObject>(error: error),
      FBFuture<AnyObject>(error: error),
    ]
    var index = 0
    let future = FBFuture<AnyObject>.onQueue(
      queue,
      resolveUntil: {
        let inner = futures[index]
        index += 1
        return inner
      })
    future.onQueue(
      queue,
      notifyOfCompletion: { inner in
        completionCalled.fulfill()
        XCTAssertEqual(inner.state, .cancelled)
      })

    wait(for: [completionCalled], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertEqual(future.state, .cancelled)
  }

  func testAsynchronousCancellationPropogates() {
    let respondCalled = XCTestExpectation(description: "Resolved Responding to Cancellation")
    let cancellationCallbackCalled = XCTestExpectation(description: "Resolved Cancellation finished")
    let future = FBMutableFuture<NSNumber>()
      .onQueue(
        queue,
        respondToCancellation: {
          respondCalled.fulfill()
          return FBFuture<NSNull>.empty()
        })

    future.cancel()
      .onQueue(
        queue,
        notifyOfCompletion: { _ in
          cancellationCallbackCalled.fulfill()
        })

    wait(for: [respondCalled, cancellationCallbackCalled], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertEqual(future.state, .cancelled)
  }

  func testCallingCancelTwiceReturnsTheSameCancellationFuture() {
    let respondCalled = XCTestExpectation(description: "Resolved Responding to Cancellation")

    let future = FBMutableFuture<NSNumber>()
      .onQueue(
        queue,
        respondToCancellation: {
          respondCalled.fulfill()
          return FBFuture<NSNull>.empty()
        })

    let cancelledFirstTime = future.cancel()
    let cancelledSecondTime = future.cancel()
    XCTAssertEqual(cancelledFirstTime, cancelledSecondTime)
  }

  func testInstallingCancellationHandlerTwiceWillCallBothCancellationHandlers() {
    let firstCancelCalled = XCTestExpectation(description: "Resolved Responding to Cancellation")
    let secondCancelCalled = XCTestExpectation(description: "Resolved Responding to Cancellation")
    let completionCalled = XCTestExpectation(description: "Resolved Completion")

    let future = FBMutableFuture<NSNumber>()
      .onQueue(
        queue,
        respondToCancellation: {
          firstCancelCalled.fulfill()
          return FBFuture<NSNull>.empty()
        }
      )
      .onQueue(
        queue,
        respondToCancellation: {
          secondCancelCalled.fulfill()
          return FBFuture<NSNull>.empty()
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { completionFuture in
          XCTAssertEqual(completionFuture.state, .cancelled)
          completionCalled.fulfill()
        })

    future.cancel()
    wait(for: [firstCancelCalled, secondCancelCalled, completionCalled], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testCancellationHandlerIsNotCalledIfFutureIsNotCancelled() {
    let completionCalled = XCTestExpectation(description: "Resolved Completion")

    let baseFuture = FBMutableFuture<NSNull>()
    baseFuture
      .onQueue(
        queue,
        respondToCancellation: {
          XCTFail("Cancellation should not have been called")
          return FBFuture<NSNull>.empty()
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { completionFuture in
          XCTAssertEqual(completionFuture.state, .done)
          completionCalled.fulfill()
        })

    baseFuture.resolve(withResult: NSNull())
    baseFuture.cancel()

    wait(for: [completionCalled], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testCancelingPropogatesOnAMappedFuture() {
    let delayedCalled = XCTestExpectation(description: "Resolved Completion")
    let delayed = FBFuture<AnyObject>(result: NSNumber(value: true))
      .delay(100)
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.state, .cancelled)
          delayedCalled.fulfill()
        })

    let chained =
      delayed
      .onQueue(
        queue,
        map: { _ in
          XCTFail("Cancellation should prevent propogation")
          return FBFuture<AnyObject>(result: NSNumber(value: false))
        })

    chained.cancel()
    wait(for: [delayedCalled], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testCancellationOfDelayedFutureWhenRacing() {
    let delayedCompletionCalled = XCTestExpectation(description: "Resolved Completion")
    let immediateCompletionCalled = XCTestExpectation(description: "Resolved Completion")
    let raceCompletionCalled = XCTestExpectation(description: "Resolved Completion")

    let delayed = FBFuture<NSNull>(result: NSNull())
      .delay(1)
      .onQueue(
        queue,
        fmap: { _ in
          XCTFail("Cancellation should prevent propogation")
          return FBFuture<AnyObject>(result: NSNumber(value: false))
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { inner in
          XCTAssertEqual(inner.state, .cancelled)
          delayedCompletionCalled.fulfill()
        })
    let immediate = FBFuture<AnyObject>(result: NSNumber(value: true))
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.result as? NSNumber, NSNumber(value: true))
          immediateCompletionCalled.fulfill()
        })
    let raced = FBFuture<AnyObject>(race: [delayed, immediate])
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.result as? NSNumber, NSNumber(value: true))
          raceCompletionCalled.fulfill()
        })

    wait(for: [delayedCompletionCalled, immediateCompletionCalled, raceCompletionCalled], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertEqual(raced.result as? NSNumber, NSNumber(value: true))
  }

  func testContextualTeardownOrdering() {
    var fmapCalled = false
    var teardownCalled = false
    let completionExpectation = XCTestExpectation(description: "Resolved Completion")
    let teardownExpectation = XCTestExpectation(description: "Resolved Teardown")

    FBFuture<AnyObject>(result: NSNumber(value: 1))
      .onQueue(
        queue,
        contextualTeardown: { value, state in
          XCTAssertTrue(fmapCalled)
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          XCTAssertEqual(state, .done)
          teardownCalled = true
          teardownExpectation.fulfill()
          return FBFuture<NSNull>.empty()
        }
      )
      .onQueue(
        queue,
        pend: { value in
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          return FBFuture<AnyObject>(result: NSNumber(value: 2))
        }
      )
      .onQueue(
        queue,
        handleError: { error in
          // should not be called and should not affect teardowns
          XCTFail()
          return FBFuture<AnyObject>(error: error)
        }
      )
      .onQueue(
        queue,
        pop: { value in
          XCTAssertFalse(teardownCalled)
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 2))
          fmapCalled = true
          return FBFuture<AnyObject>(result: NSNumber(value: 3))
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertTrue(fmapCalled)
          XCTAssertEqual(future.result as? NSNumber, NSNumber(value: 3))
          completionExpectation.fulfill()
        })

    wait(for: [completionExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    wait(for: [teardownExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testContextualTeardownWithErrorHandling() {
    let completionExpectation = XCTestExpectation(description: "Resolved Completion")
    let teardownExpectation = XCTestExpectation(description: "Resolved Teardown")
    let errorHandlingExpectation = XCTestExpectation(description: "Handled Error")

    FBFuture<AnyObject>(result: NSNumber(value: 1))
      .onQueue(
        queue,
        contextualTeardown: { value, state in
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          XCTAssertEqual(state, .done)
          teardownExpectation.fulfill()
          return FBFuture<NSNull>.empty()
        }
      )
      .onQueue(
        queue,
        pend: { _ in
          return FBFuture<AnyObject>(error: NSError(domain: "e", code: 0, userInfo: nil))
        }
      )
      .onQueue(
        queue,
        handleError: { _ in
          errorHandlingExpectation.fulfill()
          return FBFuture<AnyObject>(result: NSNumber(value: 2))
        }
      )
      .onQueue(
        queue,
        pop: { value in
          return FBFuture<AnyObject>(result: value)
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.result as? NSNumber, NSNumber(value: 2))
          completionExpectation.fulfill()
        })

    wait(for: [completionExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    wait(for: [errorHandlingExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    wait(for: [teardownExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testContextualTeardownWithErrorMapping() {
    let completionExpectation = XCTestExpectation(description: "Resolved Completion")
    let teardownExpectation = XCTestExpectation(description: "Resolved Teardown")
    let errorHandlingExpectation = XCTestExpectation(description: "Handled Error")

    FBFuture<AnyObject>(result: NSNumber(value: 1))
      .onQueue(
        queue,
        contextualTeardown: { _, _ in
          teardownExpectation.fulfill()
          return FBFuture<NSNull>.empty()
        }
      )
      .onQueue(
        queue,
        pend: { _ in
          return FBFuture<AnyObject>(error: NSError(domain: "e", code: 0, userInfo: nil))
        }
      )
      .onQueue(
        queue,
        handleError: { _ in
          errorHandlingExpectation.fulfill()
          return FBFuture<AnyObject>(error: NSError(domain: "e", code: 42, userInfo: nil))
        }
      )
      .onQueue(
        queue,
        pop: { value in
          return FBFuture<AnyObject>(result: value)
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertNotNil(future.error)
          XCTAssertEqual((future.error as NSError?)?.code, 42)
          completionExpectation.fulfill()
        })

    wait(for: [completionExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    wait(for: [errorHandlingExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    wait(for: [teardownExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testStackedTeardownBehavesLikeAStack() {
    var fmapCalled = false
    var outerTeardownCalled = false
    var innerTeardownCalled = false
    let completionExpectation = XCTestExpectation(description: "Resolved Completion")
    let outerTeardownExpectation = XCTestExpectation(description: "Resolved Outer Teardown")
    let innerTeardownExpectation = XCTestExpectation(description: "Resolved Inner Teardown")

    FBFuture<AnyObject>(result: NSNumber(value: 1))
      .onQueue(
        queue,
        contextualTeardown: { value, state in
          XCTAssertTrue(fmapCalled)
          XCTAssertTrue(innerTeardownCalled)
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          XCTAssertEqual(state, .done)
          outerTeardownCalled = true
          outerTeardownExpectation.fulfill()
          return FBFuture<NSNull>.empty().delay(1)
        }
      )
      .onQueue(
        queue,
        push: { value in
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          return FBFuture<AnyObject>(result: NSNumber(value: 2)).onQueue(
            self.queue,
            contextualTeardown: { innerValue, innerState in
              XCTAssertEqual(innerValue as? NSNumber, NSNumber(value: 2))
              XCTAssertFalse(outerTeardownCalled)
              XCTAssertEqual(innerState, .done)
              innerTeardownCalled = true
              innerTeardownExpectation.fulfill()
              return FBFuture<NSNull>.empty()
            })
        }
      )
      .onQueue(
        queue,
        pop: { value in
          XCTAssertFalse(outerTeardownCalled)
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 2))
          fmapCalled = true
          return FBFuture<AnyObject>(result: NSNumber(value: 3))
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertTrue(fmapCalled)
          XCTAssertEqual(future.result as? NSNumber, NSNumber(value: 3))
          completionExpectation.fulfill()
        })

    wait(for: [completionExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    wait(for: [outerTeardownExpectation, innerTeardownExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testReplacedTeardownStack() {
    var popCalled = false
    var firstTeardownCalled = false
    var replacedTeardownCalled = false
    let completionExpectation = XCTestExpectation(description: "Resolved Completion")
    let firstTeardownExpectation = XCTestExpectation(description: "Resolved Outer Teardown")
    let replacedTeardownExpectation = XCTestExpectation(description: "Resolved Inner Teardown")
    FBFuture<AnyObject>(result: NSNumber(value: 1))
      .onQueue(
        queue,
        contextualTeardown: { value, state in
          XCTAssertFalse(popCalled)
          XCTAssertFalse(replacedTeardownCalled)
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          XCTAssertEqual(state, .done)
          firstTeardownCalled = true
          firstTeardownExpectation.fulfill()
          return FBFuture<NSNull>.empty().delay(1)
        }
      )
      .onQueue(
        queue,
        replace: { value in
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          return FBFuture<AnyObject>(result: NSNumber(value: 2))
            .onQueue(
              self.queue,
              contextualTeardown: { innerValue, state in
                XCTAssertTrue(popCalled)
                XCTAssertEqual(innerValue as? NSNumber, NSNumber(value: 2))
                XCTAssertTrue(firstTeardownCalled)
                XCTAssertFalse(replacedTeardownCalled)
                replacedTeardownCalled = true
                replacedTeardownExpectation.fulfill()
                return FBFuture<NSNull>.empty()
              })
        }
      )
      .onQueue(
        queue,
        pop: { value in
          XCTAssertTrue(firstTeardownCalled)
          XCTAssertFalse(replacedTeardownCalled)
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 2))
          popCalled = true
          return FBFuture<AnyObject>(result: NSNumber(value: 3))
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertTrue(popCalled)
          XCTAssertEqual(future.result as? NSNumber, NSNumber(value: 3))
          completionExpectation.fulfill()
        })
    wait(for: [completionExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    wait(for: [firstTeardownExpectation, replacedTeardownExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testAdditionalTeardownOrdering() {
    var popCalled = false
    var initialTeardownCalled = false
    var subsequentTeardownCalled = false
    let completionExpectation = XCTestExpectation(description: "Resolved Completion")
    let initialTeardownExpectation = XCTestExpectation(description: "Resolved Outer Teardown")
    let subsequentTeardownExpectation = XCTestExpectation(description: "Resolved Inner Teardown")

    FBFuture<AnyObject>(result: NSNumber(value: 1))
      .onQueue(
        queue,
        contextualTeardown: { value, state in
          XCTAssertTrue(popCalled)
          XCTAssertTrue(subsequentTeardownCalled)
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          XCTAssertEqual(state, .done)
          initialTeardownCalled = true
          initialTeardownExpectation.fulfill()
          return FBFuture<NSNull>.empty()
        }
      )
      .onQueue(
        queue,
        contextualTeardown: { value, state in
          XCTAssertTrue(popCalled)
          XCTAssertFalse(initialTeardownCalled)
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          XCTAssertEqual(state, .done)
          subsequentTeardownCalled = true
          subsequentTeardownExpectation.fulfill()
          return FBFuture<NSNull>.empty().delay(1)
        }
      )
      .onQueue(
        queue,
        pop: { value in
          XCTAssertFalse(initialTeardownCalled)
          XCTAssertFalse(subsequentTeardownCalled)
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          popCalled = true
          return FBFuture<AnyObject>(result: NSNumber(value: 3))
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertTrue(popCalled)
          XCTAssertEqual(future.result as? NSNumber, NSNumber(value: 3))
          completionExpectation.fulfill()
        })

    wait(for: [completionExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    wait(for: [initialTeardownExpectation, subsequentTeardownExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testStackedErrorDoesNotResolveInnerStack() {
    let error = NSError(domain: "foo", code: 2, userInfo: nil)

    var pushCalled = false
    var outerTeardownCalled = false
    let completionExpectation = XCTestExpectation(description: "Resolved Completion")
    let outerTeardownExpectation = XCTestExpectation(description: "Resolved Outer Teardown")

    FBFuture<AnyObject>(result: NSNumber(value: 1))
      .onQueue(
        queue,
        contextualTeardown: { value, state in
          XCTAssertTrue(pushCalled)
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          XCTAssertEqual(state, .failed)
          outerTeardownCalled = true
          outerTeardownExpectation.fulfill()
          return FBFuture<NSNull>.empty()
        }
      )
      .onQueue(
        queue,
        push: { value in
          pushCalled = true
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          return FBFuture<AnyObject>(error: error).onQueue(
            self.queue,
            contextualTeardown: { _, _ in
              XCTFail("Should not resolve error teardown")
              return FBFuture<NSNull>.empty()
            })
        }
      )
      .onQueue(
        queue,
        pop: { _ in
          XCTFail("Should not resolve error mapping")
          return FBFuture<AnyObject>(error: error)
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertTrue(pushCalled)
          XCTAssertEqual(future.error as NSError?, error)
          completionExpectation.fulfill()
        })

    wait(for: [completionExpectation, outerTeardownExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testFutureToContext() {
    var teardownCalled = false
    let innerTeardownExpectation = XCTestExpectation(description: "Resolved Inner Teardown")

    FBFuture<AnyObject>(result: NSNumber(value: 1))
      .onQueue(
        queue,
        pushTeardown: { value in
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          return FBFuture<AnyObject>(result: NSNumber(value: 2))
            .onQueue(
              self.queue,
              contextualTeardown: { innerValue, state in
                XCTAssertFalse(teardownCalled)
                XCTAssertEqual(innerValue as? NSNumber, NSNumber(value: 2))
                XCTAssertEqual(state, .done)
                innerTeardownExpectation.fulfill()
                teardownCalled = true
                return FBFuture<NSNull>.empty()
              })
        }
      )
      .onQueue(
        queue,
        pop: { value in
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 2))
          XCTAssertFalse(teardownCalled)
          return FBFuture<AnyObject>(result: NSNumber(value: 3))
        })

    wait(for: [innerTeardownExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testContextToFuture() {
    var teardown: FBMutableFuture<NSNull>?
    var teardownCalled = false
    let completionExpectation = XCTestExpectation(description: "Resolved Completion")
    let teardownExpectation = XCTestExpectation(description: "Resolved Completion")

    FBFuture<AnyObject>(result: NSNumber(value: 1))
      .onQueue(
        queue,
        contextualTeardown: { value, _ in
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          teardownCalled = true
          teardownExpectation.fulfill()
          return FBFuture<NSNull>.empty()
        }
      )
      .onQueue(
        queue,
        enter: { value, innerTeardown in
          XCTAssertEqual(value as? NSNumber, NSNumber(value: 1))
          teardown = innerTeardown
          return NSNumber(value: 2)
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.result as? NSNumber, NSNumber(value: 2))
          completionExpectation.fulfill()
        })

    // Wait for the base future to resolve and confirm there's no teardown called yet.
    wait(for: [completionExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
    XCTAssertFalse(teardownCalled)

    // Now teardown the context manually.
    teardown?.resolve(withResult: NSNull())
    wait(for: [teardownExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testContextToFutureError() {
    let completionExpectation = XCTestExpectation(description: "Resolved Completion")
    let expectedError = NSError(domain: "foo", code: 0, userInfo: nil)

    FBFuture<AnyObject>(error: expectedError)
      .onQueue(
        queue,
        contextualTeardown: { _, _ in
          XCTFail("contextualTeardown should not be called when the base future errors")
          return FBFuture<NSNull>.empty()
        }
      )
      .onQueue(
        queue,
        enter: { value, _ in
          XCTFail("enter should not be called when the base future errors")
          return value
        }
      )
      .onQueue(
        queue,
        notifyOfCompletion: { future in
          XCTAssertEqual(future.error as NSError?, expectedError)
          completionExpectation.fulfill()
        })

    // Wait for the base future to resolve and confirm there's no teardown called yet.
    wait(for: [completionExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  // MARK: - Helpers

  private func assertSynchronousResolution(withBlock resolveBlock: (FBMutableFuture<NSNumber>) -> Void, expectedState state: FBFutureState, expectedResult: NSNumber?, expectedError: NSError?) {
    let future = FBMutableFuture<NSNumber>()

    resolveBlock(future)

    XCTAssertEqual(future.state, state)
    XCTAssertEqual(future.hasCompleted, true)
    XCTAssertEqual(future.result as? NSNumber, expectedResult)
    XCTAssertEqual(future.error as NSError?, expectedError)
  }

  private func waitForAsynchronousResolution(withBlock resolveBlock: @escaping (FBMutableFuture<NSNumber>) -> Void, expectedState state: FBFutureState, expectationKeyPath: String?, expectationValue: Any?) {
    let future = FBMutableFuture<NSNumber>()
    var expectations = [
      keyValueObservingExpectation(for: future, keyPath: "state", expectedValue: state.rawValue as NSNumber),
      keyValueObservingExpectation(for: future, keyPath: "hasCompleted", expectedValue: true),
    ]

    if let expectationKeyPath {
      expectations.append(keyValueObservingExpectation(for: future, keyPath: expectationKeyPath, expectedValue: expectationValue))
    }

    queue.async {
      resolveBlock(future)
    }

    wait(for: expectations, timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }
}

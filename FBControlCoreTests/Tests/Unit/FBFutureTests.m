/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBFutureTests : XCTestCase

@property (nonatomic, strong, readwrite) dispatch_queue_t queue;

@end

@implementation FBFutureTests

- (void)setUp
{
  self.queue = dispatch_queue_create("com.facebook.fbcontrolcore.tests.future", DISPATCH_QUEUE_SERIAL);
}

- (void)testResolvesSynchronouslyWithObject
{
  [self assertSynchronousResolutionWithBlock:^(FBMutableFuture *future) {
    [future resolveWithResult:@YES];
  } expectedState:FBFutureStateDone expectedResult:@YES expectedError:nil];
}

- (void)testResolvesAsynchronouslyWithObject
{
  [self waitForAsynchronousResolutionWithBlock:^(FBMutableFuture *future) {
    [future resolveWithResult:@YES];
  } expectedState:FBFutureStateDone expectationKeyPath:@"result" expectationValue:@YES];
}

- (void)testResolvesSynchronouslyWithError
{
  NSError *error = [NSError errorWithDomain:@"foo" code:2 userInfo:nil];
  [self assertSynchronousResolutionWithBlock:^(FBMutableFuture *future) {
    [future resolveWithError:error];
  } expectedState:FBFutureStateFailed expectedResult:nil expectedError:error];
}

- (void)testResolvesAsynchronouslyWithError
{
  NSError *error = [NSError errorWithDomain:@"foo" code:2 userInfo:nil];
  [self waitForAsynchronousResolutionWithBlock:^(FBMutableFuture *future) {
    [future resolveWithError:error];
  } expectedState:FBFutureStateFailed expectationKeyPath:@"error" expectationValue:error];
}

- (void)testEarlyCancellation
{
  [self assertSynchronousResolutionWithBlock:^(FBMutableFuture *future) {
    [future cancel];
  } expectedState:FBFutureStateCancelled expectedResult:nil expectedError:nil];
}

- (void)testAsynchronousCancellation
{
  [self waitForAsynchronousResolutionWithBlock:^(FBMutableFuture *future) {
    [future cancel];
  } expectedState:FBFutureStateCancelled expectationKeyPath:nil expectationValue:nil];
}

- (void)testDiscardsAllResolutionsAfterTheFirst
{
  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;

  [future resolveWithResult:@YES];

  XCTAssertEqual(future.state, FBFutureStateDone);
  XCTAssertEqual(future.hasCompleted, YES);
  XCTAssertEqual(future.result, @YES);
  XCTAssertEqual(future.error, nil);

  [future resolveWithError:[NSError errorWithDomain:@"foo" code:0 userInfo:nil]];

  XCTAssertEqual(future.state, FBFutureStateDone);
  XCTAssertEqual(future.hasCompleted, YES);
  XCTAssertEqual(future.result, @YES);
  XCTAssertEqual(future.error, nil);
}

- (void)testCallbacks
{
  FBMutableFuture *future = FBMutableFuture.future;
  __block NSUInteger handlerCount = 0;
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *_) {
    @synchronized (self)
    {
      handlerCount++;
    }
  }];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *_) {
    @synchronized (self)
    {
      handlerCount++;
    }
  }];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *_) {
    @synchronized (self)
    {
      handlerCount++;
    }
  }];
  dispatch_async(self.queue, ^{
    [future resolveWithResult:@YES];
  });
  NSPredicate *prediate = [NSPredicate predicateWithBlock:^ BOOL (id _, id __) {
    @synchronized (self)
    {
      return handlerCount == 3;
    }
  }];
  XCTestExpectation *expectation = [self expectationForPredicate:prediate evaluatedWithObject:self handler:nil];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testDoActionCallback
{
  XCTestExpectation *actionExpectation = [[XCTestExpectation alloc] initWithDescription:@"Action Callback called"];
  XCTestExpectation *completionExpectation = [[XCTestExpectation alloc] initWithDescription:@"Completion called"];
  __block BOOL actionCalled = NO;

  [[[FBFuture
    futureWithResult:@YES]
    onQueue:self.queue doOnResolved:^(NSNumber *value) {
      XCTAssertEqual(value, @YES);
      actionCalled = YES;
      [actionExpectation fulfill];
    }]
    onQueue:self.queue notifyOfCompletion:^(FBFuture<NSNumber *> *future) {
      XCTAssertEqual(future.result, @YES);
      XCTAssertTrue(actionCalled);
      [completionExpectation fulfill];
    }];

  [self waitForExpectations:@[actionExpectation, completionExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testCompositeSuccess
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Composite Callback is called"];

  FBMutableFuture<NSNumber *> *future1 = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *future2 = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *future3 = FBMutableFuture.future;
  FBFuture *compositeFuture = [[FBFuture
    futureWithFutures:@[future1, future2, future3]]
    onQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0) notifyOfCompletion:^(FBFuture *future) {
      [expectation fulfill];
    }];

  dispatch_async(self.queue, ^{
    [future1 resolveWithResult:@YES];
  });
  dispatch_async(self.queue, ^{
    [future2 resolveWithResult:@NO];
  });
  dispatch_async(self.queue, ^{
    [future3 resolveWithResult:@10];
  });

  NSArray *expected = @[@YES, @NO, @10];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(compositeFuture.state, FBFutureStateDone);
  XCTAssertEqualObjects(compositeFuture.result, expected);
}

- (void)testCompositeImmediateValue
{
  FBFuture<NSArray<NSNumber *> *> *compositeFuture = [FBFuture futureWithFutures:@[
    [FBFuture futureWithResult:@0],
    [FBFuture futureWithResult:@1],
    [FBFuture futureWithResult:@2],
  ]];

  XCTAssertEqual(compositeFuture.state, FBFutureStateDone);
  XCTAssertEqualObjects(compositeFuture.result, (@[@0, @1, @2]));
}

- (void)testCompositeEmpty
{
  FBFuture<id> *compositeFuture = [FBFuture futureWithFutures:@[]];

  XCTAssertEqual(compositeFuture.state, FBFutureStateDone);
  XCTAssertEqualObjects(compositeFuture.result, (@[]));
}

- (void)testCompositeFailure
{
  NSError *error = [NSError errorWithDomain:@"foo" code:2 userInfo:nil];
  FBMutableFuture<id> *pending = FBMutableFuture.future;
  FBFuture<NSArray<NSNumber *> *> *compositeFuture = [FBFuture futureWithFutures:@[
    [FBFuture futureWithResult:@0],
    pending,
    [FBMutableFuture futureWithError:error],
  ]];

  XCTAssertEqual(compositeFuture.state, FBFutureStateFailed);
  XCTAssertEqualObjects(compositeFuture.error, error);
  XCTAssertEqual(pending.state, FBFutureStateRunning);
}

- (void)testCompositeCancellation
{
  FBMutableFuture<id> *pending = FBMutableFuture.future;
  FBMutableFuture<id> *cancelled = FBMutableFuture.future;
  [cancelled cancel];
  FBFuture<NSArray<NSNumber *> *> *compositeFuture = [FBFuture futureWithFutures:@[
    [FBFuture futureWithResult:@0],
    pending,
    cancelled,
  ]];

  XCTAssertEqual(compositeFuture.state, FBFutureStateCancelled);
  XCTAssertEqual(pending.state, FBFutureStateRunning);
}

- (void)testFmappedSuccess
{
  XCTestExpectation *step1 = [[XCTestExpectation alloc] initWithDescription:@"fmap 1 is called"];
  XCTestExpectation *step2 = [[XCTestExpectation alloc] initWithDescription:@"fmap 2 is called"];
  XCTestExpectation *step3 = [[XCTestExpectation alloc] initWithDescription:@"Completion is called"];

  FBMutableFuture<NSNumber *> *baseFuture = FBMutableFuture.future;
  FBFuture<NSNumber *> *chainFuture = [[[baseFuture
    onQueue:self.queue fmap:^(id value) {
      XCTAssertEqualObjects(value, @1);
      [step1 fulfill];
      return [FBFuture futureWithResult:@2];
    }]
    onQueue:self.queue fmap:^(id value) {
      XCTAssertEqualObjects(value, @2);
      [step2 fulfill];
      return [FBFuture futureWithResult:@3];
    }]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertEqualObjects(future.result, @3);
      [step3 fulfill];
    }];
  dispatch_async(self.queue, ^{
    [baseFuture resolveWithResult:@1];
  });

  [self waitForExpectations:@[step1, step2, step3] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(chainFuture.state, FBFutureStateDone);
  XCTAssertEqualObjects(chainFuture.result, @3);
}

- (void)testTerminateFmapOnError
{
  XCTestExpectation *step1 = [[XCTestExpectation alloc] initWithDescription:@"fmap 1 is called"];
  XCTestExpectation *step2 = [[XCTestExpectation alloc] initWithDescription:@"fmap 2 is called"];
  XCTestExpectation *step3 = [[XCTestExpectation alloc] initWithDescription:@"Completion is called"];
  NSError *error = [NSError errorWithDomain:@"foo" code:2 userInfo:nil];

  FBMutableFuture<NSNumber *> *baseFuture = FBMutableFuture.future;
  FBFuture<NSNumber *> *chainFuture = [[[[baseFuture
    onQueue:self.queue fmap:^(id value) {
      XCTAssertEqualObjects(value, @1);
      [step1 fulfill];
      return [FBFuture futureWithResult:@2];
    }]
    onQueue:self.queue fmap:^(id value) {
      XCTAssertEqualObjects(value, @2);
      [step2 fulfill];
      return [FBFuture futureWithError:error];
    }]
    onQueue:self.queue fmap:^FBFuture *(id _) {
      XCTFail(@"Chained block should not be called after failure");
      return [FBFuture futureWithError:error];
    }]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertEqualObjects(future.error, error);
      [step3 fulfill];
    }];
  dispatch_async(self.queue, ^{
    [baseFuture resolveWithResult:@1];
  });

  [self waitForExpectations:@[step1, step2, step3] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(chainFuture.state, FBFutureStateFailed);
  XCTAssertEqualObjects(chainFuture.error, error);
}

- (void)testAsyncTimeout
{
  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;

  NSError *error = nil;
  id value = [future awaitWithTimeout:1 error:&error];
  XCTAssertNil(value);
  XCTAssertNotNil(error);
}

- (void)testAsyncResolution
{
  FBMutableFuture *future = FBMutableFuture.future;
  dispatch_async(self.queue, ^{
    [future resolveWithResult:@YES];
  });

  NSError *error = nil;
  id value = [future awaitWithTimeout:1 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(value, @YES);
}

- (void)testAsyncErrorPropogation
{
  NSError *expected = [NSError errorWithDomain:@"foo" code:0 userInfo:nil];
  FBMutableFuture *future = FBMutableFuture.future;
  dispatch_async(self.queue, ^{
    [future resolveWithError:expected];
  });

  NSError *error = nil;
  id value = [future awaitWithTimeout:1 error:&error];
  XCTAssertNil(value);
  XCTAssertEqualObjects(error, expected);
}

- (void)testAsyncCancellation
{
  FBMutableFuture *future = FBMutableFuture.future;
  dispatch_async(self.queue, ^{
    [future cancel];
  });

  NSError *error = nil;
  id value = [future awaitWithTimeout:1 error:&error];
  XCTAssertNil(value);
  XCTAssertNotNil(error.description);
}

- (void)testChainValueThenError
{
  XCTestExpectation *step1 = [[XCTestExpectation alloc] initWithDescription:@"chain1 is called"];
  XCTestExpectation *step2 = [[XCTestExpectation alloc] initWithDescription:@"chain2 is called"];
  XCTestExpectation *step3 = [[XCTestExpectation alloc] initWithDescription:@"chain3 is called"];
  XCTestExpectation *step4 = [[XCTestExpectation alloc] initWithDescription:@"Completion is called"];
  NSError *error = [NSError errorWithDomain:@"foo" code:2 userInfo:nil];

  FBMutableFuture<NSNumber *> *baseFuture = FBMutableFuture.future;
  FBFuture<NSNumber *> *chainFuture = [[[[baseFuture
    onQueue:self.queue chain:^(FBFuture *future) {
      XCTAssertEqualObjects(future.result, @1);
      [step1 fulfill];
      return [FBFuture futureWithResult:@2];
    }]
    onQueue:self.queue chain:^(FBFuture *future) {
      XCTAssertEqualObjects(future.result, @2);
      [step2 fulfill];
      return [FBFuture futureWithError:error];
    }]
    onQueue:self.queue chain:^FBFuture *(FBFuture *future) {
      XCTAssertEqualObjects(future.error, error);
      [step3 fulfill];
      return [FBFuture futureWithResult:@4];
    }]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertEqualObjects(future.result, @4);
      [step4 fulfill];
    }];
  dispatch_async(self.queue, ^{
    [baseFuture resolveWithResult:@1];
  });

  [self waitForExpectations:@[step1, step2, step3, step4] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(chainFuture.state, FBFutureStateDone);
  XCTAssertEqualObjects(chainFuture.result, @4);
}

- (void)testChainingToHandleCancellation
{
  XCTestExpectation *completion = [[XCTestExpectation alloc] initWithDescription:@"completion is called"];
  XCTestExpectation *chained = [[XCTestExpectation alloc] initWithDescription:@"chain is called"];
  XCTestExpectation *remapped = [[XCTestExpectation alloc] initWithDescription:@"fmap on handling cancellation"];

  FBMutableFuture<NSNumber *> *baseFuture = FBMutableFuture.future;
  FBFuture<NSNumber *> *chainFuture = [[[baseFuture
    onQueue:self.queue chain:^(FBFuture *future) {
      [chained fulfill];
      return [FBFuture futureWithResult:@2];
    }]
    onQueue:self.queue fmap:^(id _) {
      [remapped fulfill];
      return [FBFuture futureWithResult:@3];
    }]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateDone);
      XCTAssertEqual(future.result, @3);
      [completion fulfill];
    }];
  dispatch_async(self.queue, ^{
    [baseFuture cancel];
  });

  [self waitForExpectations:@[completion, chained, remapped] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(chainFuture.state, FBFutureStateDone);
  XCTAssertEqual(chainFuture.result, @3);
}

- (void)testUnhandledCancellationWillPropogate
{
  XCTestExpectation *firstChain = [[XCTestExpectation alloc] initWithDescription:@"first chain is called"];
  XCTestExpectation *secondChain = [[XCTestExpectation alloc] initWithDescription:@"second chain is called"];
  XCTestExpectation *completion = [[XCTestExpectation alloc] initWithDescription:@"completion is called"];

  FBMutableFuture<NSNumber *> *baseFuture = FBMutableFuture.future;
  FBFuture<NSNumber *> *chainFuture = [[[[baseFuture
    onQueue:self.queue chain:^(FBFuture *_) {
      [firstChain fulfill];
      FBMutableFuture *future = FBMutableFuture.future;
      [future cancel];
      return future;
    }]
    onQueue:self.queue chain:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateCancelled);
      [secondChain fulfill];
      return future;
    }]
    onQueue:self.queue fmap:^(id _) {
      XCTFail(@"fmap should not be called");
      return FBMutableFuture.future;
    }]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateCancelled);
      [completion fulfill];
    }];
  dispatch_async(self.queue, ^{
    [baseFuture resolveWithResult:@0];
  });

  [self waitForExpectations:@[firstChain, secondChain, completion] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(chainFuture.state, FBFutureStateCancelled);
}

- (void)testRaceSuccessFutures
{
  XCTestExpectation *completion = [[XCTestExpectation alloc] initWithDescription:@"Completion is called"];
  XCTestExpectation *late1Cancelled = [[XCTestExpectation alloc] initWithDescription:@"Cancellation of late future 1"];
  XCTestExpectation *late2Cancelled = [[XCTestExpectation alloc] initWithDescription:@"Cancellation of late future 2"];

  FBFuture<NSNumber *> *lateFuture1 = [[FBMutableFuture
    future]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateCancelled);
      [late1Cancelled fulfill];
    }];
  FBFuture<NSNumber *> *lateFuture2 = [[FBMutableFuture
    future]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateCancelled);
      [late2Cancelled fulfill];
    }];
  FBFuture<NSNumber *> *raceFuture = [[FBFuture
    race:@[
      lateFuture1,
      [FBFuture futureWithResult:@1],
      lateFuture2,
    ]]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateDone);
      XCTAssertEqualObjects(future.result, @1);
      [completion fulfill];
    }];

  [self waitForExpectations:@[completion, late1Cancelled, late2Cancelled] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(raceFuture.state, FBFutureStateDone);
  XCTAssertEqualObjects(raceFuture.result, @1);
  XCTAssertEqual(lateFuture1.state, FBFutureStateCancelled);
  XCTAssertEqual(lateFuture2.state, FBFutureStateCancelled);
}

- (void)testAllCancelledPropogates
{
  XCTestExpectation *completion = [[XCTestExpectation alloc] initWithDescription:@"Completion is called"];
  XCTestExpectation *cancel1Called = [[XCTestExpectation alloc] initWithDescription:@"Cancellation of late future 1"];
  XCTestExpectation *cancel2Called = [[XCTestExpectation alloc] initWithDescription:@"Cancellation of late future 2"];
  XCTestExpectation *cancel3Called = [[XCTestExpectation alloc] initWithDescription:@"Cancellation of late future 3"];

  FBFuture<NSNumber *> *cancelFuture1 = [[FBMutableFuture
    future]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateCancelled);
      [cancel1Called fulfill];
    }];
  FBFuture<NSNumber *> *cancelFuture2 = [[FBMutableFuture
    future]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateCancelled);
      [cancel2Called fulfill];
    }];
  FBFuture<NSNumber *> *cancelFuture3 = [[FBMutableFuture
    future]
      onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
        XCTAssertEqual(future.state, FBFutureStateCancelled);
      [cancel3Called fulfill];
    }];

  FBFuture<NSNumber *> *raceFuture = [[FBFuture
    race:@[
      cancelFuture1,
      cancelFuture2,
      cancelFuture3,
    ]]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateCancelled);
      [completion fulfill];
    }];

  dispatch_async(self.queue, ^{
    [cancelFuture1 cancel];
  });
  dispatch_async(self.queue, ^{
    [cancelFuture2 cancel];
  });
  dispatch_async(self.queue, ^{
    [cancelFuture3 cancel];
  });

  [self waitForExpectations:@[completion, cancel1Called, cancel2Called, cancel3Called] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(raceFuture.state, FBFutureStateCancelled);
  XCTAssertEqual(cancelFuture1.state, FBFutureStateCancelled);
  XCTAssertEqual(cancelFuture2.state, FBFutureStateCancelled);
  XCTAssertEqual(cancelFuture3.state, FBFutureStateCancelled);
}

- (void)testImmediateValue
{
  NSError *error = [NSError errorWithDomain:@"foo" code:0 userInfo:nil];
  FBFuture<NSNumber *> *successFuture = [FBFuture futureWithResult:@1];
  FBFuture<NSNumber *> *errorFuture = [FBFuture futureWithError:error];

  XCTAssertEqual(successFuture.state, FBFutureStateDone);
  XCTAssertEqualObjects(successFuture.result, @1);
  XCTAssertEqual(errorFuture.state, FBFutureStateFailed);
  XCTAssertEqualObjects(errorFuture.error, error);
}

- (void)testImmedateValueInRaceBasedOnOrdering
{
  NSError *error = [NSError errorWithDomain:@"foo" code:0 userInfo:nil];
  FBFuture<NSNumber *> *raceFuture = [FBFuture race:@[
    [FBFuture futureWithResult:@1],
    [FBFuture futureWithError:error],
    [FBMutableFuture future],
  ]];
  XCTAssertEqual(raceFuture.state, FBFutureStateDone);
  XCTAssertEqualObjects(raceFuture.result, @1);

  raceFuture = [FBFuture race:@[
    [FBFuture futureWithError:error],
    [FBMutableFuture future],
    [FBFuture futureWithResult:@2],
  ]];
  XCTAssertEqual(raceFuture.state, FBFutureStateFailed);
  XCTAssertEqualObjects(raceFuture.error, error);
}

- (void)testAsyncConstructor
{
  XCTestExpectation *resultCalled = [[XCTestExpectation alloc] initWithDescription:@"Result Future"];
  XCTestExpectation *errorCalled = [[XCTestExpectation alloc] initWithDescription:@"Error Future"];
  XCTestExpectation *cancelCalled = [[XCTestExpectation alloc] initWithDescription:@"Cancel Future"];

  NSError *error = [NSError errorWithDomain:@"foo" code:0 userInfo:nil];
  FBFuture *resultFuture = [FBFuture onQueue:self.queue resolve:^FBFuture *{
    [resultCalled fulfill];
    return [FBFuture futureWithResult:@0];
  }];
  FBFuture *errorFuture = [FBFuture onQueue:self.queue resolve:^FBFuture *{
    [errorCalled fulfill];
    return [FBFuture futureWithError:error];
  }];
  FBFuture *cancelFuture = [FBFuture onQueue:self.queue resolve:^FBFuture *{
    FBMutableFuture *future = [FBMutableFuture future];
    [future cancel];
    [cancelCalled fulfill];
    return future;
  }];

  [self waitForExpectations:@[resultCalled, errorCalled, cancelCalled] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(resultFuture.state, FBFutureStateDone);
  XCTAssertEqual(errorFuture.state, FBFutureStateFailed);
  XCTAssertEqual(cancelFuture.state, FBFutureStateCancelled);
}

- (void)testTimedOutIn
{
  FBFuture *future = [[FBFuture new] timeout:0.1 waitingFor:@"Some Condition"];

  XCTAssertFalse(future.hasCompleted);
  XCTAssertEqual(future.state, FBFutureStateRunning);
  XCTAssertNil(future.result);
  XCTAssertNil(future.error);

  [self waitForExpectations:@[
    [self keyValueObservingExpectationForObject:future keyPath:@"hasCompleted" expectedValue:@YES],
    [self keyValueObservingExpectationForObject:future keyPath:@"state" expectedValue:@(FBFutureStateFailed)]
  ] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testResolveWhen
{
  __block NSInteger resolveCount = 2;
  FBFuture<NSNull *> *future = [FBFuture onQueue:self.queue resolveWhen:^BOOL {
    --resolveCount;
    return resolveCount == 0;
  }];

  [self waitForExpectations:@[
    [self keyValueObservingExpectationForObject:future keyPath:@"hasCompleted" expectedValue:@YES],
    [self keyValueObservingExpectationForObject:future keyPath:@"result" expectedValue:@YES],
    [self keyValueObservingExpectationForObject:future keyPath:@"state" expectedValue:@(FBFutureStateDone)]
  ] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testChainReplaceSuccessful
{
  FBMutableFuture<NSNumber *> *replacement = FBMutableFuture.future;
  FBFuture<NSNumber *> *future = [[[FBFuture futureWithResult:@NO] chainReplace:replacement] delay:0.1];
  dispatch_async(self.queue, ^{
    [replacement resolveWithResult:@YES];
  });

  [self waitForExpectations:@[
    [self keyValueObservingExpectationForObject:future keyPath:@"result" expectedValue:@YES],
    [self keyValueObservingExpectationForObject:future keyPath:@"state" expectedValue:@(FBFutureStateDone)]
  ] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testChainReplaceFailing
{
  NSError *error = [NSError errorWithDomain:@"foo" code:0 userInfo:nil];
  FBMutableFuture<NSNumber *> *replacement = FBMutableFuture.future;
  FBFuture<NSNumber *> *future = [[[FBFuture futureWithError:error] chainReplace:replacement] delay:0.1];
  dispatch_async(self.queue, ^{
    [replacement resolveWithResult:@YES];
  });

  [self waitForExpectations:@[
    [self keyValueObservingExpectationForObject:future keyPath:@"result" expectedValue:@YES],
    [self keyValueObservingExpectationForObject:future keyPath:@"state" expectedValue:@(FBFutureStateDone)]
  ] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testFallback
{
  NSError *error = [NSError errorWithDomain:@"foo" code:0 userInfo:nil];
  FBFuture<NSNumber *> *future = [[[FBFuture futureWithError:error] fallback:@YES] delay:0.1];

  [self waitForExpectations:@[
    [self keyValueObservingExpectationForObject:future keyPath:@"result" expectedValue:@YES],
    [self keyValueObservingExpectationForObject:future keyPath:@"state" expectedValue:@(FBFutureStateDone)]
  ] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testRepeatedResolution
{
  XCTestExpectation *completionCalled = [[XCTestExpectation alloc] initWithDescription:@"Resolved outer Completion"];
  NSError *error = [NSError errorWithDomain:@"foo" code:2 userInfo:nil];
  NSArray<FBFuture<NSNumber *> *> *futures = @[
    [FBFuture futureWithError:error],
    [FBFuture futureWithError:error],
    [FBFuture futureWithError:error],
    [FBFuture futureWithResult:@YES],
  ];
  __block NSUInteger index = 0;
  FBFuture<NSNumber *> *future = [FBFuture onQueue:self.queue resolveUntil:^{
    FBFuture<NSNumber *> *inner = futures[index];
    index++;
    return inner;
  }];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture<NSNumber *> *inner) {
    [completionCalled fulfill];
    XCTAssertEqualObjects(inner.result, @YES);
  }];

  [self waitForExpectations:@[completionCalled] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(future.state, FBFutureStateDone);
  XCTAssertEqualObjects(future.result, @YES);
}

- (void)testCancelledResolution
{
  XCTestExpectation *completionCalled = [[XCTestExpectation alloc] initWithDescription:@"Resolved outer Completion"];
  NSError *error = [NSError errorWithDomain:@"foo" code:2 userInfo:nil];
  FBFuture<NSNumber *> *cancelledFuture = [FBMutableFuture future];
  [cancelledFuture cancel];
  NSArray<FBFuture<NSNumber *> *> *futures = @[
    [FBFuture futureWithError:error],
    cancelledFuture,
    [FBFuture futureWithError:error],
    [FBFuture futureWithError:error],
  ];
  __block NSUInteger index = 0;
  FBFuture<NSNumber *> *future = [FBFuture onQueue:self.queue resolveUntil:^{
    FBFuture<NSNumber *> *inner = futures[index];
    index++;
    return inner;
  }];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture<NSNumber *> *inner) {
    [completionCalled fulfill];
    XCTAssertEqual(inner.state, FBFutureStateCancelled);
  }];

  [self waitForExpectations:@[completionCalled] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(future.state, FBFutureStateCancelled);
}

- (void)testAsynchronousCancellationPropogates
{
  XCTestExpectation *respondCalled = [[XCTestExpectation alloc] initWithDescription:@"Resolved Responding to Cancellation"];
  XCTestExpectation *cancellationCallbackCalled = [[XCTestExpectation alloc] initWithDescription:@"Resolved Cancellation finished"];
  FBFuture<NSNumber *> *future = [[FBMutableFuture
    future]
    onQueue:self.queue respondToCancellation:^{
      [respondCalled fulfill];
      return FBFuture.empty;
    }];

  [[future
    cancel]
    onQueue:self.queue notifyOfCompletion:^(id _) {
      [cancellationCallbackCalled fulfill];
    }];

  [self waitForExpectations:@[respondCalled, cancellationCallbackCalled] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(future.state, FBFutureStateCancelled);
}

- (void)testCallingCancelTwiceReturnsTheSameCancellationFuture
{
  XCTestExpectation *respondCalled = [[XCTestExpectation alloc] initWithDescription:@"Resolved Responding to Cancellation"];

  FBFuture<NSNumber *> *future = [[FBMutableFuture
    future]
    onQueue:self.queue respondToCancellation:^{
      [respondCalled fulfill];
      return FBFuture.empty;
    }];

  FBFuture<NSNull *> *cancelledFirstTime = [future cancel];
  FBFuture<NSNull *> *cancelledSecondTime = [future cancel];
  XCTAssertEqual(cancelledFirstTime, cancelledSecondTime);
}

- (void)testInstallingCancellationHandlerTwiceWillCallBothCancellationHandlers
{
  XCTestExpectation *firstCancelCalled = [[XCTestExpectation alloc] initWithDescription:@"Resolved Responding to Cancellation"];
  XCTestExpectation *secondCancelCalled = [[XCTestExpectation alloc] initWithDescription:@"Resolved Responding to Cancellation"];
  XCTestExpectation *completionCalled = [[XCTestExpectation alloc] initWithDescription:@"Resolved Completion"];

  FBFuture<NSNumber *> *future = [[[[FBMutableFuture
    future]
    onQueue:self.queue respondToCancellation:^{
      [firstCancelCalled fulfill];
      return FBFuture.empty;
    }]
    onQueue:self.queue respondToCancellation:^{
      [secondCancelCalled fulfill];
      return FBFuture.empty;
    }]
    onQueue:self.queue notifyOfCompletion:^(FBFuture<NSNull *> *completionFuture) {
      XCTAssertEqual(completionFuture.state, FBFutureStateCancelled);
      [completionCalled fulfill];
    }];

  [future cancel];
  [self waitForExpectations:@[firstCancelCalled, secondCancelCalled, completionCalled] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testCancellationHandlerIsNotCalledIfFutureIsNotCancelled
{
  XCTestExpectation *completionCalled = [[XCTestExpectation alloc] initWithDescription:@"Resolved Completion"];

  FBMutableFuture<NSNull *> *baseFuture = FBMutableFuture.future;
  [[baseFuture
    onQueue:self.queue respondToCancellation:^{
      XCTFail(@"Cancellation should not have been called");
      return FBFuture.empty;
    }]
    onQueue:self.queue notifyOfCompletion:^(FBFuture<NSNull *> *completionFuture) {
      XCTAssertEqual(completionFuture.state, FBFutureStateDone);
      [completionCalled fulfill];
    }];

  [baseFuture resolveWithResult:NSNull.null];
  [baseFuture cancel];

  [self waitForExpectations:@[completionCalled] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testCancelingPropogatesOnAMappedFuture
{
  XCTestExpectation *delayedCalled = [[XCTestExpectation alloc] initWithDescription:@"Resolved Completion"];
  FBFuture *delayed = [[[FBFuture
    futureWithResult:@YES]
    delay:100]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateCancelled);
      [delayedCalled fulfill];
    }];

  FBFuture *chained = [delayed
    onQueue:self.queue map:^(id _) {
      XCTFail(@"Cancellation should prevent propogation");
      return [FBFuture futureWithResult:@NO];
    }];

  [chained cancel];
  [self waitForExpectations:@[delayedCalled] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testCancellationOfDelayedFutureWhenRacing
{
  XCTestExpectation *delayedCompletionCalled = [[XCTestExpectation alloc] initWithDescription:@"Resolved Completion"];
  XCTestExpectation *immediateCompletionCalled = [[XCTestExpectation alloc] initWithDescription:@"Resolved Completion"];
  XCTestExpectation *raceCompletionCalled = [[XCTestExpectation alloc] initWithDescription:@"Resolved Completion"];

  FBFuture *delayed = [[[[FBFuture
    futureWithResult:NSNull.null]
    delay:1]
    onQueue:self.queue fmap:^(id _) {
      XCTFail(@"Cancellation should prevent propogation");
      return [FBFuture futureWithResult:@NO];
    }]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *inner) {
      XCTAssertEqual(inner.state, FBFutureStateCancelled);
      [delayedCompletionCalled fulfill];
    }];
  FBFuture *immediate = [[FBFuture
    futureWithResult:@YES]
    onQueue:self.queue notifyOfCompletion:^(FBFuture<NSNumber *> *future) {
      XCTAssertEqualObjects(future.result, @YES);
      [immediateCompletionCalled fulfill];
    }];
  FBFuture *raced = [[FBFuture
    race:@[delayed, immediate]]
    onQueue:self.queue notifyOfCompletion:^(FBFuture<NSNumber *> *future) {
      XCTAssertEqualObjects(future.result, @YES);
      [raceCompletionCalled fulfill];
    }];

  [self waitForExpectations:@[delayedCompletionCalled, immediateCompletionCalled, raceCompletionCalled] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqualObjects(raced.result, @YES);
}

- (void)testContextualTeardownOrdering
{
  __block BOOL fmapCalled = NO;
  __block BOOL teardownCalled = NO;
  XCTestExpectation *completionExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Completion"];
  XCTestExpectation *teardownExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Teardown"];

  [[[[[FBFuture
    futureWithResult:@1]
    onQueue:self.queue contextualTeardown:^(id value, FBFutureState state){
      XCTAssertTrue(fmapCalled);
      XCTAssertEqualObjects(value, @1);
      XCTAssertEqual(state, FBFutureStateDone);
      teardownCalled = YES;
      [teardownExpectation fulfill];
      return FBFuture.empty;
    }]
    onQueue:self.queue pend:^(id value) {
      XCTAssertEqualObjects(value, @1);
      return [FBFuture futureWithResult:@2];
    }]
    onQueue:self.queue pop:^(id value) {
      XCTAssertFalse(teardownCalled);
      XCTAssertEqualObjects(value, @2);
      fmapCalled = YES;
      return [FBFuture futureWithResult:@3];
    }]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertTrue(fmapCalled);
      XCTAssertEqualObjects(future.result, @3);
      [completionExpectation fulfill];
    }];

  [self waitForExpectations:@[completionExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  [self waitForExpectations:@[teardownExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testStackedTeardownBehavesLikeAStack
{
  __block BOOL fmapCalled = NO;
  __block BOOL outerTeardownCalled = NO;
  __block BOOL innerTeardownCalled = NO;
  XCTestExpectation *completionExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Completion"];
  XCTestExpectation *outerTeardownExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Outer Teardown"];
  XCTestExpectation *innerTeardownExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Inner Teardown"];

  [[[[[FBFuture
    futureWithResult:@1]
    onQueue:self.queue contextualTeardown:^(id value, FBFutureState state){
      XCTAssertTrue(fmapCalled);
      XCTAssertTrue(innerTeardownCalled);
      XCTAssertEqualObjects(value, @1);
      XCTAssertEqual(state, FBFutureStateDone);
      outerTeardownCalled = YES;
      [outerTeardownExpectation fulfill];
      return [FBFuture.empty delay:1];
    }]
    onQueue:self.queue push:^(id value) {
      XCTAssertEqualObjects(value, @1);
      return [[FBFuture futureWithResult:@2] onQueue:self.queue contextualTeardown:^(id innerValue, FBFutureState innerState) {
        XCTAssertEqualObjects(innerValue, @2);
        XCTAssertFalse(outerTeardownCalled);
        XCTAssertEqual(innerState, FBFutureStateDone);
        innerTeardownCalled = YES;
        [innerTeardownExpectation fulfill];
        return FBFuture.empty;
      }];
    }]
    onQueue:self.queue pop:^(id value) {
      XCTAssertFalse(outerTeardownCalled);
      XCTAssertEqualObjects(value, @2);
      fmapCalled = YES;
      return [FBFuture futureWithResult:@3];
    }]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertTrue(fmapCalled);
      XCTAssertEqualObjects(future.result, @3);
      [completionExpectation fulfill];
    }];

  [self waitForExpectations:@[completionExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  [self waitForExpectations:@[outerTeardownExpectation, innerTeardownExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testReplacedTeardownStack
{
  __block BOOL popCalled = NO;
  __block BOOL firstTeardownCalled = NO;
  __block BOOL replacedTeardownCalled = NO;
  XCTestExpectation *completionExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Completion"];
  XCTestExpectation *firstTeardownExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Outer Teardown"];
  XCTestExpectation *replacedTeardownExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Inner Teardown"];
  [[[[[FBFuture
    futureWithResult:@1]
    onQueue:self.queue contextualTeardown:^(NSNumber *value, FBFutureState state){
      XCTAssertFalse(popCalled);
      XCTAssertFalse(replacedTeardownCalled);
      XCTAssertEqualObjects(value, @1);
      XCTAssertEqual(state, FBFutureStateDone);
      firstTeardownCalled = YES;
      [firstTeardownExpectation fulfill];
      return [FBFuture.empty delay:1];
    }]
    onQueue:self.queue replace:^(NSNumber *value) {
     XCTAssertEqualObjects(value, @1);
     return [[FBFuture
       futureWithResult:@2]
       onQueue:self.queue contextualTeardown:^(NSNumber *innerValue, FBFutureState state) {
         XCTAssertTrue(popCalled);
         XCTAssertEqualObjects(innerValue, @2);
         XCTAssertTrue(firstTeardownCalled);
         XCTAssertFalse(replacedTeardownCalled);
         replacedTeardownCalled = YES;
         [replacedTeardownExpectation fulfill];
         return FBFuture.empty;
       }];
    }]
    onQueue:self.queue pop:^(NSNumber *value) {
      XCTAssertTrue(firstTeardownCalled);
      XCTAssertFalse(replacedTeardownCalled);
      XCTAssertEqualObjects(value, @2);
      popCalled = YES;
      return [FBFuture futureWithResult:@3];
    }]
   onQueue:self.queue notifyOfCompletion:^(FBFuture<NSNumber *> *future) {
     XCTAssertTrue(popCalled);
     XCTAssertEqualObjects(future.result, @3);
     [completionExpectation fulfill];
   }];
  [self waitForExpectations:@[completionExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  [self waitForExpectations:@[firstTeardownExpectation, replacedTeardownExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}


- (void)testAdditionalTeardownOrdering
{
  __block BOOL popCalled = NO;
  __block BOOL initialTeardownCalled = NO;
  __block BOOL subsequentTeardownCalled = NO;
  XCTestExpectation *completionExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Completion"];
  XCTestExpectation *initialTeardownExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Outer Teardown"];
  XCTestExpectation *subsequentTeardownExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Inner Teardown"];

  [[[[[FBFuture
    futureWithResult:@1]
    onQueue:self.queue contextualTeardown:^(id value, FBFutureState state){
      XCTAssertTrue(popCalled);
      XCTAssertTrue(subsequentTeardownCalled);
      XCTAssertEqualObjects(value, @1);
      XCTAssertEqual(state, FBFutureStateDone);
      initialTeardownCalled = YES;
      [initialTeardownExpectation fulfill];
      return [FBFuture empty];
    }]
    onQueue:self.queue contextualTeardown:^(id value, FBFutureState state){
      XCTAssertTrue(popCalled);
      XCTAssertFalse(initialTeardownCalled);
      XCTAssertEqualObjects(value, @1);
      XCTAssertEqual(state, FBFutureStateDone);
      subsequentTeardownCalled = YES;
      [subsequentTeardownExpectation fulfill];
      return [FBFuture.empty delay:1];
    }]
    onQueue:self.queue pop:^(id value) {
      XCTAssertFalse(initialTeardownCalled);
      XCTAssertFalse(subsequentTeardownCalled);
      XCTAssertEqualObjects(value, @1);
      popCalled = YES;
      return [FBFuture futureWithResult:@3];
    }]
   onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
     XCTAssertTrue(popCalled);
     XCTAssertEqualObjects(future.result, @3);
     [completionExpectation fulfill];
   }];

  [self waitForExpectations:@[completionExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  [self waitForExpectations:@[initialTeardownExpectation, subsequentTeardownExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testStackedErrorDoesNotResolveInnerStack
{
  NSError *error = [NSError errorWithDomain:@"foo" code:2 userInfo:nil];

  __block BOOL pushCalled = NO;
  __block BOOL outerTeardownCalled = NO;
  XCTestExpectation *completionExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Completion"];
  XCTestExpectation *outerTeardownExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Outer Teardown"];

  [[[[[FBFuture
    futureWithResult:@1]
    onQueue:self.queue contextualTeardown:^(id value, FBFutureState state){
        XCTAssertTrue(pushCalled);
        XCTAssertEqualObjects(value, @1);
        XCTAssertEqual(state, FBFutureStateFailed);
        outerTeardownCalled = YES;
        [outerTeardownExpectation fulfill];
        return FBFuture.empty;
    }]
    onQueue:self.queue push:^(id value) {
      pushCalled = YES;
      XCTAssertEqualObjects(value, @1);
      return [[FBFuture futureWithError:error] onQueue:self.queue contextualTeardown:^(id innerValue, FBFutureState innerState) {
        XCTFail(@"Should not resolve error teardown");
        return FBFuture.empty;
      }];
    }]
    onQueue:self.queue pop:^(id result) {
      XCTFail(@"Should not resolve error mapping");
      return [FBFuture futureWithError:error];
    }]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertTrue(pushCalled);
      XCTAssertEqualObjects(future.error, error);
      [completionExpectation fulfill];
    }];

  [self waitForExpectations:@[completionExpectation, outerTeardownExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testFutureToContext
{
  __block BOOL teardownCalled = NO;
  XCTestExpectation *innerTeardownExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Inner Teardown"];

  [[[FBFuture
    futureWithResult:@1]
    onQueue:self.queue pushTeardown:^(id value) {
      XCTAssertEqualObjects(value, @1);
      return [[FBFuture
        futureWithResult:@2]
        onQueue:self.queue contextualTeardown:^(id innerValue, FBFutureState state) {
          XCTAssertFalse(teardownCalled);
          XCTAssertEqualObjects(innerValue, @2);
          XCTAssertEqual(state, FBFutureStateDone);
          [innerTeardownExpectation fulfill];
          teardownCalled = YES;
          return FBFuture.empty;
        }];
    }]
    onQueue:self.queue pop:^(id value) {
      XCTAssertEqualObjects(value, @2);
      XCTAssertFalse(teardownCalled);
      return [FBFuture futureWithResult:@3];
    }];

  [self waitForExpectations:@[innerTeardownExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testContextToFuture
{
  __block FBMutableFuture<NSNull *> *teardown = nil;
  __block BOOL teardownCalled = NO;
  XCTestExpectation *completionExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Completion"];
  XCTestExpectation *teardownExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved Completion"];

  [[[[FBFuture
    futureWithResult:@1]
    onQueue:self.queue contextualTeardown:^(NSNumber *value, FBFutureState state) {
      XCTAssertEqualObjects(value, @1);
      teardownCalled = YES;
      [teardownExpectation fulfill];
      return FBFuture.empty;
    }]
    onQueue:self.queue enter:^(id value, FBMutableFuture<NSNull *> *innerTeardown) {
      XCTAssertEqualObjects(value, @1);
      teardown = innerTeardown;
      return @2;
    }]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      XCTAssertEqualObjects(future.result, @2);
      [completionExpectation fulfill];
    }];

  // Wait for the base future to resolve and confirm there's no teardown called yet.
  [self waitForExpectations:@[completionExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertFalse(teardownCalled);

  // Now teardown the context manually.
  [teardown resolveWithResult:NSNull.null];
  [self waitForExpectations:@[teardownExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

#pragma mark - Helpers

- (void)assertSynchronousResolutionWithBlock:(void (^)(FBMutableFuture *))resolveBlock expectedState:(FBFutureState)state expectedResult:(id)expectedResult expectedError:(NSError *)expectedError
{
  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;

  resolveBlock(future);

  XCTAssertEqual(future.state, state);
  XCTAssertEqual(future.hasCompleted, YES);
  XCTAssertEqual(future.result, expectedResult);
  XCTAssertEqual(future.error, expectedError);
}

- (void)waitForAsynchronousResolutionWithBlock:(void (^)(FBMutableFuture *))resolveBlock expectedState:(FBFutureState)state expectationKeyPath:(NSString *)expectationKeyPath expectationValue:(id)expectationValue
{
  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;
  NSArray *expectations = @[
    [self keyValueObservingExpectationForObject:future keyPath:@"state" expectedValue:@(state)],
    [self keyValueObservingExpectationForObject:future keyPath:@"hasCompleted" expectedValue:@YES],
  ];

  if (expectationKeyPath != nil) {
    expectations = [expectations arrayByAddingObject:[self keyValueObservingExpectationForObject:future keyPath:expectationKeyPath expectedValue:expectationValue]];
  }

  dispatch_async(self.queue, ^{
    resolveBlock(future);
  });

  [self waitForExpectations:expectations timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBFutureTests : XCTestCase

@property (nonatomic, strong, readwrite) dispatch_queue_t queue;

@end

@implementation FBFutureTests

- (void)setUp
{
  self.queue = dispatch_queue_create("com.facebook.fbcontrolcore.tests.future", DISPATCH_QUEUE_CONCURRENT);
}

- (void)testResolvesWithObject
{
  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;
  dispatch_async(self.queue, ^{
    [future resolveWithResult:@YES];
  });

  [self waitForExpectations:@[
    [self keyValueObservingExpectationForObject:future keyPath:@"result" expectedValue:@YES],
    [self keyValueObservingExpectationForObject:future keyPath:@"hasCompleted" expectedValue:@YES],
    [self keyValueObservingExpectationForObject:future keyPath:@"state" expectedValue:@(FBFutureStateCompletedWithResult)],
  ] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testResolvesWithError
{
  NSError *error = [NSError errorWithDomain:@"foo" code:0 userInfo:nil];
  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;
  dispatch_async(self.queue, ^{
    [future resolveWithError:error];
  });

  [self waitForExpectations:@[
    [self keyValueObservingExpectationForObject:future keyPath:@"error" expectedValue:error],
    [self keyValueObservingExpectationForObject:future keyPath:@"hasCompleted" expectedValue:@YES],
    [self keyValueObservingExpectationForObject:future keyPath:@"state" expectedValue:@(FBFutureStateCompletedWithError)],
  ] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testEarlyCancellation
{
  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;
  dispatch_async(self.queue, ^{
    [future cancel];
  });

  [self waitForExpectations:@[
    [self keyValueObservingExpectationForObject:future keyPath:@"hasCompleted" expectedValue:@YES],
    [self keyValueObservingExpectationForObject:future keyPath:@"state" expectedValue:@(FBFutureStateCompletedWithCancellation)],
  ] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testDiscardsAllResolutionsAfterTheFirst
{
  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;
  dispatch_async(self.queue, ^{
    [future resolveWithResult:@YES];
  });

  [self waitForExpectations:@[
    [self keyValueObservingExpectationForObject:future keyPath:@"result" expectedValue:@YES],
    [self keyValueObservingExpectationForObject:future keyPath:@"hasCompleted" expectedValue:@YES],
    [self keyValueObservingExpectationForObject:future keyPath:@"state" expectedValue:@(FBFutureStateCompletedWithResult)],
  ] timeout:FBControlCoreGlobalConfiguration.fastTimeout];

  [future resolveWithError:[NSError errorWithDomain:@"foo" code:0 userInfo:nil]];

  XCTAssertEqualObjects(future.result, @YES);
  XCTAssertNil(future.error);
  XCTAssertEqual(future.state, FBFutureStateCompletedWithResult);
}

- (void)testCallbacks
{
  FBMutableFuture *future = FBMutableFuture.future;
  __block NSUInteger handlerCount = 0;
  [future notifyOfCompletionOnQueue:self.queue handler:^(FBFuture *_) {
    @synchronized (self)
    {
      handlerCount++;
    }
  }];
  [future notifyOfCompletionOnQueue:self.queue handler:^(FBFuture *_) {
    @synchronized (self)
    {
      handlerCount++;
    }
  }];
  [future notifyOfCompletionOnQueue:self.queue handler:^(FBFuture *_) {
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

- (void)testCompositeSuccess
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Composite Callback is called"];

  FBMutableFuture<NSNumber *> *future1 = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *future2 = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *future3 = FBMutableFuture.future;
  FBFuture *compositeFuture = [[FBFuture
    futureWithFutures:@[future1, future2, future3]]
    notifyOfCompletionOnQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0) handler:^(FBFuture *future) {
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
  XCTAssertEqual(compositeFuture.state, FBFutureStateCompletedWithResult);
  XCTAssertEqualObjects(compositeFuture.result, expected);
}

- (void)testCompositeImmediateValue
{
  FBFuture<NSArray<NSNumber *> *> *compositeFuture = [FBFuture futureWithFutures:@[
    [FBFuture futureWithResult:@0],
    [FBFuture futureWithResult:@1],
    [FBFuture futureWithResult:@2],
  ]];

  XCTAssertEqual(compositeFuture.state, FBFutureStateCompletedWithResult);
  XCTAssertEqualObjects(compositeFuture.result, (@[@0, @1, @2]));
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
    notifyOfCompletionOnQueue:self.queue handler:^(FBFuture *future) {
      XCTAssertEqualObjects(future.result, @3);
      [step3 fulfill];
    }];
  dispatch_async(self.queue, ^{
    [baseFuture resolveWithResult:@1];
  });

  [self waitForExpectations:@[step1, step2, step3] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(chainFuture.state, FBFutureStateCompletedWithResult);
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
    notifyOfCompletionOnQueue:self.queue handler:^(FBFuture *future) {
      XCTAssertEqualObjects(future.error, error);
      [step3 fulfill];
    }];
  dispatch_async(self.queue, ^{
    [baseFuture resolveWithResult:@1];
  });

  [self waitForExpectations:@[step1, step2, step3] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(chainFuture.state, FBFutureStateCompletedWithError);
  XCTAssertEqualObjects(chainFuture.error, error);
}

- (void)testAsyncTimeout
{
  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;

  NSError *error = nil;
  id value = [NSRunLoop.currentRunLoop awaitCompletionOfFuture:future timeout:1 error:&error];
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
  id value = [NSRunLoop.currentRunLoop awaitCompletionOfFuture:future timeout:1 error:&error];
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
  id value = [NSRunLoop.currentRunLoop awaitCompletionOfFuture:future timeout:1 error:&error];
  XCTAssertNil(value);
  XCTAssertEqualObjects(error, expected);
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
    notifyOfCompletionOnQueue:self.queue handler:^(FBFuture *future) {
      XCTAssertEqualObjects(future.result, @4);
      [step4 fulfill];
    }];
  dispatch_async(self.queue, ^{
    [baseFuture resolveWithResult:@1];
  });

  [self waitForExpectations:@[step1, step2, step3, step4] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(chainFuture.state, FBFutureStateCompletedWithResult);
  XCTAssertEqualObjects(chainFuture.result, @4);
}

- (void)testChainValueThenCancel
{
  XCTestExpectation *completion = [[XCTestExpectation alloc] initWithDescription:@"Completion is called"];
  XCTestExpectation *cancellation = [[XCTestExpectation alloc] initWithDescription:@"Cancellation is called"];

  FBMutableFuture<NSNumber *> *baseFuture = FBMutableFuture.future;
  FBFuture<NSNumber *> *chainFuture = [[[[baseFuture
    onQueue:self.queue chain:^(FBFuture *future) {
      XCTFail(@"Chain Should Not be called for cancelled future");
      return [FBFuture futureWithResult:@2];
    }]
    onQueue:self.queue fmap:^(id _) {
     XCTFail(@"fmap Should Not be called for cancelled future");
     return [FBFuture futureWithResult:@3];
    }]
    notifyOfCompletionOnQueue:self.queue handler:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateCompletedWithCancellation);
      [completion fulfill];
    }]
    notifyOfCancellationOnQueue:self.queue handler:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateCompletedWithCancellation);
      [cancellation fulfill];
    }];
  dispatch_async(self.queue, ^{
    [baseFuture cancel];
  });

  [self waitForExpectations:@[completion, cancellation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(chainFuture.state, FBFutureStateCompletedWithCancellation);
}

- (void)testChainedCancellation
{
  XCTestExpectation *chain = [[XCTestExpectation alloc] initWithDescription:@"chain is called"];
  XCTestExpectation *cancellation = [[XCTestExpectation alloc] initWithDescription:@"Cancellation is called"];
  XCTestExpectation *completion = [[XCTestExpectation alloc] initWithDescription:@"Completion is called"];

  FBMutableFuture<NSNumber *> *baseFuture = FBMutableFuture.future;
  FBFuture<NSNumber *> *chainFuture = [[[[baseFuture
    onQueue:self.queue chain:^(FBFuture *_) {
      [chain fulfill];
      FBMutableFuture *future = FBMutableFuture.future;
      [future cancel];
      return future;
    }]
    onQueue:self.queue chain:^(id _) {
      XCTFail(@"chain Should Not be called for cancelled future");
      return [FBFuture futureWithResult:@3];
    }]
    notifyOfCompletionOnQueue:self.queue handler:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateCompletedWithCancellation);
      [completion fulfill];
    }]
    notifyOfCancellationOnQueue:self.queue handler:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateCompletedWithCancellation);
      [cancellation fulfill];
    }];
  dispatch_async(self.queue, ^{
    [baseFuture resolveWithResult:@0];
  });

  [self waitForExpectations:@[chain, completion, cancellation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(chainFuture.state, FBFutureStateCompletedWithCancellation);
}

- (void)testRaceSuccessFutures
{
  XCTestExpectation *completion = [[XCTestExpectation alloc] initWithDescription:@"Completion is called"];
  XCTestExpectation *late1Cancelled = [[XCTestExpectation alloc] initWithDescription:@"Cancellation of late future 1"];
  XCTestExpectation *late2Cancelled = [[XCTestExpectation alloc] initWithDescription:@"Cancellation of late future 2"];

  FBFuture<NSNumber *> *lateFuture1 = [[FBMutableFuture
    future]
    notifyOfCancellationOnQueue:self.queue handler:^(FBFuture *_) {
      [late1Cancelled fulfill];
    }];
  FBFuture<NSNumber *> *lateFuture2 = [[FBMutableFuture
    future]
    notifyOfCancellationOnQueue:self.queue handler:^(FBFuture *_) {
      [late2Cancelled fulfill];
    }];
  FBFuture<NSNumber *> *raceFuture = [[FBFuture
    race:@[
      lateFuture1,
      [FBFuture futureWithResult:@1],
      lateFuture2,
    ]]
    notifyOfCompletionOnQueue:self.queue handler:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateCompletedWithResult);
      XCTAssertEqualObjects(future.result, @1);
      [completion fulfill];
    }];

  [self waitForExpectations:@[completion, late1Cancelled, late2Cancelled] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(raceFuture.state, FBFutureStateCompletedWithResult);
  XCTAssertEqualObjects(raceFuture.result, @1);
  XCTAssertEqual(lateFuture1.state, FBFutureStateCompletedWithCancellation);
  XCTAssertEqual(lateFuture2.state, FBFutureStateCompletedWithCancellation);
}

- (void)testAllCancelledPropogates
{
  XCTestExpectation *completion = [[XCTestExpectation alloc] initWithDescription:@"Completion is called"];
  XCTestExpectation *cancel1Called = [[XCTestExpectation alloc] initWithDescription:@"Cancellation of late future 1"];
  XCTestExpectation *cancel2Called = [[XCTestExpectation alloc] initWithDescription:@"Cancellation of late future 2"];
  XCTestExpectation *cancel3Called = [[XCTestExpectation alloc] initWithDescription:@"Cancellation of late future 3"];

  FBFuture<NSNumber *> *cancelFuture1 = [[FBMutableFuture
    future]
    notifyOfCancellationOnQueue:self.queue handler:^(FBFuture *_) {
      [cancel1Called fulfill];
    }];
  FBFuture<NSNumber *> *cancelFuture2 = [[FBMutableFuture
    future]
    notifyOfCancellationOnQueue:self.queue handler:^(FBFuture *_) {
      [cancel2Called fulfill];
    }];
  FBFuture<NSNumber *> *cancelFuture3 = [[FBMutableFuture
    future]
    notifyOfCancellationOnQueue:self.queue handler:^(FBFuture *_) {
      [cancel3Called fulfill];
    }];

  FBFuture<NSNumber *> *raceFuture = [[FBFuture
    race:@[
      cancelFuture1,
      cancelFuture2,
      cancelFuture3,
    ]]
    notifyOfCompletionOnQueue:self.queue handler:^(FBFuture *future) {
      XCTAssertEqual(future.state, FBFutureStateCompletedWithCancellation);
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
  XCTAssertEqual(raceFuture.state, FBFutureStateCompletedWithCancellation);
  XCTAssertEqual(cancelFuture1.state, FBFutureStateCompletedWithCancellation);
  XCTAssertEqual(cancelFuture2.state, FBFutureStateCompletedWithCancellation);
  XCTAssertEqual(cancelFuture3.state, FBFutureStateCompletedWithCancellation);
}

- (void)testImmediateValue
{
  NSError *error = [NSError errorWithDomain:@"foo" code:0 userInfo:nil];
  FBFuture<NSNumber *> *successFuture = [FBFuture futureWithResult:@1];
  FBFuture<NSNumber *> *errorFuture = [FBFuture futureWithError:error];

  XCTAssertEqual(successFuture.state, FBFutureStateCompletedWithResult);
  XCTAssertEqualObjects(successFuture.result, @1);
  XCTAssertEqual(errorFuture.state, FBFutureStateCompletedWithError);
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
  XCTAssertEqual(raceFuture.state, FBFutureStateCompletedWithResult);
  XCTAssertEqualObjects(raceFuture.result, @1);

  raceFuture = [FBFuture race:@[
    [FBFuture futureWithError:error],
    [FBMutableFuture future],
    [FBFuture futureWithResult:@2],
  ]];
  XCTAssertEqual(raceFuture.state, FBFutureStateCompletedWithError);
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
    [cancelCalled fulfill];
    FBMutableFuture *future = [FBMutableFuture future];
    [future cancel];
    return future;
  }];

  [self waitForExpectations:@[resultCalled, errorCalled, cancelCalled] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
  XCTAssertEqual(resultFuture.state, FBFutureStateCompletedWithResult);
  XCTAssertEqual(errorFuture.state, FBFutureStateCompletedWithError);
  XCTAssertEqual(cancelFuture.state, FBFutureStateCompletedWithCancellation);
}

@end

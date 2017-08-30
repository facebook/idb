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

- (void)testChainedSuccess
{
  XCTestExpectation *step1 = [[XCTestExpectation alloc] initWithDescription:@"Chain 1 is called"];
  XCTestExpectation *step2 = [[XCTestExpectation alloc] initWithDescription:@"Chain 2 is called"];
  XCTestExpectation *step3 = [[XCTestExpectation alloc] initWithDescription:@"Completion is called"];

  FBMutableFuture<NSNumber *> *baseFuture = FBMutableFuture.future;
  FBFuture<NSNumber *> *chainFuture = [[[baseFuture
    onQueue:self.queue chain:^(id value) {
      XCTAssertEqualObjects(value, @1);
      [step1 fulfill];
      return [FBFuture futureWithResult:@2];
    }]
    onQueue:self.queue chain:^(id value) {
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

- (void)testTerminateChainOnError
{
  XCTestExpectation *step1 = [[XCTestExpectation alloc] initWithDescription:@"Chain 1 is called"];
  XCTestExpectation *step2 = [[XCTestExpectation alloc] initWithDescription:@"Chain 2 is called"];
  XCTestExpectation *step3 = [[XCTestExpectation alloc] initWithDescription:@"Completion is called"];
  NSError *error = [NSError errorWithDomain:@"foo" code:2 userInfo:nil];

  FBMutableFuture<NSNumber *> *baseFuture = FBMutableFuture.future;
  FBFuture<NSNumber *> *chainFuture = [[[[baseFuture
    onQueue:self.queue chain:^(id value) {
      XCTAssertEqualObjects(value, @1);
      [step1 fulfill];
      return [FBFuture futureWithResult:@2];
    }]
    onQueue:self.queue chain:^(id value) {
      XCTAssertEqualObjects(value, @2);
      [step2 fulfill];
      return [FBFuture futureWithError:error];
    }]
    onQueue:self.queue chain:^FBFuture *(id _) {
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

@end

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBFutureAdditionalTests : XCTestCase

@property (nonatomic, strong, readwrite) dispatch_queue_t queue;

@end

@implementation FBFutureAdditionalTests

- (void)setUp
{
  self.queue = dispatch_queue_create("com.facebook.fbcontrolcore.tests.future.additional", DISPATCH_QUEUE_SERIAL);
}

#pragma mark - resolveValue (synchronous)

- (void)testResolveValueSuccess
{
  FBFuture *future = [FBFuture resolveValue:^id(NSError **error) {
    return @42;
  }];
  XCTAssertEqual(future.state, FBFutureStateDone, @"Synchronous resolveValue with result should be done");
  XCTAssertEqualObjects(future.result, @42, @"Result should be the returned value");
}

- (void)testResolveValueFailure
{
  NSError *expectedError = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
  FBFuture *future = [FBFuture resolveValue:^id(NSError **error) {
    *error = expectedError;
    return nil;
  }];
  XCTAssertEqual(future.state, FBFutureStateFailed, @"Synchronous resolveValue returning nil should fail");
  XCTAssertEqualObjects(future.error, expectedError, @"Error should be the provided error");
}

#pragma mark - onQueue:resolveValue: (asynchronous)

- (void)testOnQueueResolveValueSuccess
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Async resolve value"];
  FBFuture *future = [FBFuture onQueue:self.queue resolveValue:^id(NSError **error) {
    return @99;
  }];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *resolved) {
    XCTAssertEqualObjects(resolved.result, @99, @"Async resolved value should be 99");
    [expectation fulfill];
  }];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testOnQueueResolveValueFailure
{
  NSError *expectedError = [NSError errorWithDomain:@"async" code:2 userInfo:nil];
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Async resolve error"];
  FBFuture *future = [FBFuture onQueue:self.queue resolveValue:^id(NSError **error) {
    *error = expectedError;
    return nil;
  }];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *resolved) {
    XCTAssertEqualObjects(resolved.error, expectedError, @"Async resolved error should match");
    [expectation fulfill];
  }];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

#pragma mark - mapReplace

- (void)testMapReplaceOnSuccess
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"mapReplace completion"];
  FBFuture *future = [[FBFuture futureWithResult:@1] mapReplace:@"replaced"];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *resolved) {
    XCTAssertEqualObjects(resolved.result, @"replaced", @"mapReplace should replace the result value");
    [expectation fulfill];
  }];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testMapReplaceOnError
{
  NSError *error = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"mapReplace error"];
  FBFuture *future = [[FBFuture futureWithError:error] mapReplace:@"replaced"];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *resolved) {
    XCTAssertEqualObjects(resolved.error, error, @"mapReplace on error should propagate the error");
    [expectation fulfill];
  }];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

#pragma mark - rephraseFailure

- (void)testRephraseFailureOnError
{
  NSError *originalError = [NSError errorWithDomain:@"original" code:1 userInfo:nil];
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"rephraseFailure"];
  FBFuture *future = [[FBFuture futureWithError:originalError] rephraseFailure:@"Rephrased: %@", @"context"];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *resolved) {
    XCTAssertNotNil(resolved.error, @"Rephrased future should still have an error");
    XCTAssertTrue([resolved.error.localizedDescription containsString:@"Rephrased: context"],
                  @"Error should contain rephrased message, got: %@", resolved.error.localizedDescription);
    [expectation fulfill];
  }];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testRephraseFailureOnSuccessPassesThrough
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"rephraseFailure success"];
  FBFuture *future = [[FBFuture futureWithResult:@42] rephraseFailure:@"Should not appear"];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *resolved) {
    XCTAssertEqualObjects(resolved.result, @42, @"rephraseFailure on success should pass through the result");
    XCTAssertNil(resolved.error, @"rephraseFailure on success should have no error");
    [expectation fulfill];
  }];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

#pragma mark - handleError

- (void)testHandleErrorRecovery
{
  NSError *error = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"handleError recovery"];
  FBFuture *future = [[FBFuture futureWithError:error] onQueue:self.queue handleError:^(NSError *err) {
    return [FBFuture futureWithResult:@"recovered"];
  }];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *resolved) {
    XCTAssertEqualObjects(resolved.result, @"recovered", @"handleError should recover from error");
    [expectation fulfill];
  }];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testHandleErrorNotCalledOnSuccess
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"handleError not called"];
  FBFuture *future = [[FBFuture futureWithResult:@"ok"] onQueue:self.queue handleError:^(NSError *err) {
    XCTFail(@"handleError should not be called on success");
    return [FBFuture futureWithResult:@"bad"];
  }];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *resolved) {
    XCTAssertEqualObjects(resolved.result, @"ok", @"Success should pass through handleError unchanged");
    [expectation fulfill];
  }];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

#pragma mark - map

- (void)testMapTransformsResult
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"map"];
  FBFuture *future = [[FBFuture futureWithResult:@5] onQueue:self.queue map:^(NSNumber *value) {
    return @(value.integerValue * 2);
  }];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *resolved) {
    XCTAssertEqualObjects(resolved.result, @10, @"map should transform the result");
    [expectation fulfill];
  }];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testMapPropagatesError
{
  NSError *error = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"map error"];
  FBFuture *future = [[FBFuture futureWithError:error] onQueue:self.queue map:^(id value) {
    XCTFail(@"map should not be called on error");
    return value;
  }];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *resolved) {
    XCTAssertEqualObjects(resolved.error, error, @"Error should propagate through map");
    [expectation fulfill];
  }];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

#pragma mark - Cancel on Already Completed Future

- (void)testCancelOnAlreadyDoneFuturePreservesState
{
  FBFuture *future = [FBFuture futureWithResult:@1];
  FBFuture<NSNull *> *cancelResult = [future cancel];
  XCTAssertEqual(cancelResult.state, FBFutureStateDone, @"Cancel on done future should return resolved empty future");
  XCTAssertEqual(future.state, FBFutureStateDone, @"State should remain done after cancel attempt");
  XCTAssertEqualObjects(future.result, @1, @"Result should be preserved after cancel attempt");
}

- (void)testCancelOnAlreadyFailedFuturePreservesState
{
  NSError *error = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
  FBFuture *future = [FBFuture futureWithError:error];
  FBFuture<NSNull *> *cancelResult = [future cancel];
  XCTAssertEqual(cancelResult.state, FBFutureStateDone, @"Cancel on failed future should return resolved empty future");
  XCTAssertEqual(future.state, FBFutureStateFailed, @"State should remain failed after cancel attempt");
}

#pragma mark - resolveFromFuture with Already Completed Futures

- (void)testResolveFromAlreadyCompletedFuture
{
  FBFuture *source = [FBFuture futureWithResult:@"source"];
  FBMutableFuture *target = FBMutableFuture.future;
  [target resolveFromFuture:source];
  XCTAssertEqual(target.state, FBFutureStateDone, @"Target should resolve immediately from completed source");
  XCTAssertEqualObjects(target.result, @"source", @"Target should have source's result");
}

- (void)testResolveFromAlreadyFailedFuture
{
  NSError *error = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
  FBFuture *source = [FBFuture futureWithError:error];
  FBMutableFuture *target = FBMutableFuture.future;
  [target resolveFromFuture:source];
  XCTAssertEqual(target.state, FBFutureStateFailed, @"Target should resolve immediately from failed source");
  XCTAssertEqualObjects(target.error, error, @"Target should have source's error");
}

- (void)testResolveFromCancelledFuture
{
  FBMutableFuture *source = FBMutableFuture.future;
  [source cancel];
  FBMutableFuture *target = FBMutableFuture.future;
  [target resolveFromFuture:source];
  XCTAssertEqual(target.state, FBFutureStateCancelled, @"Target should be cancelled from cancelled source");
}

#pragma mark - Fallback on Success

- (void)testFallbackOnSuccessPreservesResult
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"fallback success"];
  FBFuture *future = [[FBFuture futureWithResult:@"original"] fallback:@"fallback"];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *resolved) {
    XCTAssertEqualObjects(resolved.result, @"original", @"Fallback should not replace successful result");
    [expectation fulfill];
  }];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

#pragma mark - FBFutureContext Composite

- (void)testFutureContextWithFutureContextsCombinesResults
{
  FBFutureContext *ctx1 = [FBFutureContext futureContextWithResult:@"a"];
  FBFutureContext *ctx2 = [FBFutureContext futureContextWithResult:@"b"];
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"composite context"];
  FBFutureContext *composite = [FBFutureContext futureContextWithFutureContexts:@[ctx1, ctx2]];
  [composite.future onQueue:self.queue notifyOfCompletion:^(FBFuture *resolved) {
    NSArray *expected = @[@"a", @"b"];
    XCTAssertEqualObjects(resolved.result, expected, @"Composite context should combine results");
    [expectation fulfill];
  }];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

#pragma mark - Notification on Already Completed Future

- (void)testNotifyOfCompletionOnAlreadyResolvedFuture
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"notify already resolved"];
  FBFuture *future = [FBFuture futureWithResult:@"done"];
  [future onQueue:self.queue notifyOfCompletion:^(FBFuture *resolved) {
    XCTAssertEqualObjects(resolved.result, @"done", @"Handler should fire even on already-resolved future");
    [expectation fulfill];
  }];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

#pragma mark - Cancellation with No Responders

- (void)testCancelWithNoCancellationResponders
{
  FBMutableFuture *future = FBMutableFuture.future;
  FBFuture<NSNull *> *cancelFuture = [future cancel];
  XCTAssertEqual(future.state, FBFutureStateCancelled, @"Future should be cancelled");
  XCTAssertNotNil(cancelFuture, @"Cancel should return a non-nil future");
  XCTAssertEqual(cancelFuture.state, FBFutureStateDone, @"Cancel future with no responders should resolve immediately");
}

@end

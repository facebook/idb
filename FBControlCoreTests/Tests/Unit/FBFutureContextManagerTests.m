/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBFutureContextManagerTests : XCTestCase <FBFutureContextManagerDelegate>

@property (nonatomic, strong, readwrite) dispatch_queue_t queue;
@property (nonatomic, assign, readwrite) NSUInteger prepareCalled;
@property (atomic, assign, readwrite) NSUInteger teardownCalled;
@property (nonatomic, copy, readwrite) NSNumber *contextPoolTimeout;
@property (nonatomic, assign, readwrite) BOOL failPrepare;
@property (nonatomic, assign, readwrite) BOOL resetFailPrepare; // if YES, set failPrepare = NO when prepare fails
@property (nonatomic, assign, readwrite) BOOL isContextSharable;
@property (nonatomic, strong, readwrite) id<FBControlCoreLogger> logger;

@end

@implementation FBFutureContextManagerTests

- (void)setUp
{
  self.queue = dispatch_queue_create("com.facebook.fbcontrolcore.tests.future_context", DISPATCH_QUEUE_SERIAL);
  self.logger = [FBControlCoreGlobalConfiguration.defaultLogger withName:@"manager_test"];
  self.isContextSharable = NO;
  self.contextPoolTimeout = nil;
  self.prepareCalled = 0;
  self.teardownCalled = 0;
  self.failPrepare = NO;
  self.resetFailPrepare = NO;
}

- (FBFutureContextManager<NSNumber *> *)manager
{
  return [FBFutureContextManager managerWithQueue:self.queue delegate:self logger:self.logger];
}

- (void)testSingleAquire
{
  FBFuture *future = [[self.manager
    utilizeWithPurpose:@"A Test"]
    onQueue:self.queue pop:^(id result) {
      return [FBFuture futureWithResult:@123];
    }];

  NSError *error = nil;
  id value = [future awaitWithTimeout:1 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(value, @123);

  XCTAssertEqual(self.prepareCalled, 1u);
  XCTAssertEqual(self.teardownCalled, 1u);
}

- (void)testSequentialAquire
{
  FBFutureContextManager<NSNumber *> *manager = self.manager;

  FBFuture *future0 = [[manager
    utilizeWithPurpose:@"A Test"]
    onQueue:self.queue pop:^(id result) {
      return [FBFuture futureWithResult:@0];
    }];

  NSError *error = nil;
  id value = [future0 awaitWithTimeout:1 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(value, @0);

  XCTAssertEqual(self.prepareCalled, 1u);
  XCTAssertEqual(self.teardownCalled, 1u);

  FBFuture *future1 = [[manager
    utilizeWithPurpose:@"A Test"]
    onQueue:self.queue pop:^(id result) {
      return [FBFuture futureWithResult:@1];
    }];
  value = [future1 awaitWithTimeout:1 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(value, @1);

  XCTAssertEqual(self.prepareCalled, 2u);
  XCTAssertEqual(self.teardownCalled, 2u);
}

- (void)testSequentialAquireWithCooloff
{
  FBFutureContextManager<NSNumber *> *manager = self.manager;
  self.contextPoolTimeout = @0.2;

  FBFuture *future0 = [[manager
    utilizeWithPurpose:@"A Test"]
    onQueue:self.queue pop:^(id result) {
      return [FBFuture futureWithResult:@0];
    }];

  NSError *error = nil;
  id value = [future0 awaitWithTimeout:1 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(value, @0);

  XCTAssertEqual(self.prepareCalled, 1u);
  XCTAssertEqual(self.teardownCalled, 0u);

  FBFuture *future1 = [[manager
    utilizeWithPurpose:@"A Test"]
    onQueue:self.queue pop:^(id result) {
      return [FBFuture futureWithResult:@1];
    }];
  value = [future1 awaitWithTimeout:1 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(value, @1);

  XCTAssertEqual(self.prepareCalled, 1u);
  XCTAssertEqual(self.teardownCalled, 0u);

  [[FBFuture futureWithDelay:0.25 future:FBFuture.empty] await:nil];

  XCTAssertEqual(self.prepareCalled, 1u);
  XCTAssertEqual(self.teardownCalled, 1u);
}

- (void)testConcurrentAquireOnlyPreparesOnce
{
  FBFutureContextManager<NSNumber *> *manager = self.manager;
  dispatch_queue_t concurrent = dispatch_queue_create("com.facebook.fbcontrolcore.tests.future_context.concurrent", DISPATCH_QUEUE_CONCURRENT);
  FBMutableFuture *future0 = FBMutableFuture.future;
  FBMutableFuture *future1 = FBMutableFuture.future;
  FBMutableFuture *future2 = FBMutableFuture.future;

  dispatch_async(concurrent, ^{
    FBFuture *inner = [[manager
      utilizeWithPurpose:@"Test 0"]
      onQueue:self.queue pop:^(id result) {
        [self.logger log:@"Test 0 In Use"];
        return [FBFuture futureWithResult:@0];
      }];
    [future0 resolveFromFuture:inner];
  });
  dispatch_async(concurrent, ^{
    FBFuture *inner = [[manager
      utilizeWithPurpose:@"Test 1"]
      onQueue:self.queue pop:^(id result) {
        [self.logger log:@"Test 1 In Use"];
        return [FBFuture futureWithResult:@1];
      }];
    [future1 resolveFromFuture:inner];
  });
  dispatch_async(concurrent, ^{
    FBFuture *inner = [[manager
      utilizeWithPurpose:@"Test 2"]
      onQueue:self.queue pop:^(id result) {
        [self.logger log:@"Test 2 In Use"];
        return [FBFuture futureWithResult:@2];
      }];
    [future2 resolveFromFuture:inner];
  });

  NSError *error = nil;
  id value = [[FBFuture futureWithFutures:@[future0, future1, future2]] awaitWithTimeout:1 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(value, (@[@0, @1, @2]));

  XCTAssertEqual(self.prepareCalled, 1u);
  XCTAssertEqual(self.teardownCalled, 1u);
}

- (void)testConcurrentAquireWithSharableResource
{
  FBFutureContextManager<NSNumber *> *manager = self.manager;
  self.isContextSharable = YES;
  dispatch_queue_t concurrent = dispatch_queue_create("com.facebook.fbcontrolcore.tests.future_context.concurrent", DISPATCH_QUEUE_CONCURRENT);
  FBMutableFuture *future0 = FBMutableFuture.future;
  FBMutableFuture *future1 = FBMutableFuture.future;
  FBMutableFuture *future2 = FBMutableFuture.future;

  dispatch_async(concurrent, ^{
    FBFuture *inner = [[manager
      utilizeWithPurpose:@"Test 0"]
      onQueue:self.queue pop:^(id result) {
        [self.logger log:@"Test 0 In Use"];
        return [FBFuture futureWithResult:@0];
      }];
    [future0 resolveFromFuture:inner];
  });
  dispatch_async(concurrent, ^{
    FBFuture *inner = [[manager
      utilizeWithPurpose:@"Test 1"]
      onQueue:self.queue pop:^(id result){
        [self.logger log:@"Test 1 In Use"];
        return [FBFuture futureWithResult:@1];
      }];
    [future1 resolveFromFuture:inner];
  });
  dispatch_async(concurrent, ^{
    FBFuture *inner = [[manager
      utilizeWithPurpose:@"Test 2"]
      onQueue:self.queue pop:^(id result) {
        [self.logger log:@"Test 2 In Use"];
        return [FBFuture futureWithResult:@2];
      }];
    [future2 resolveFromFuture:inner];
  });

  NSError *error = nil;
  id value = [[FBFuture futureWithFutures:@[future0, future1, future2]] awaitWithTimeout:1 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(value, (@[@0, @1, @2]));

  XCTAssertEqual(self.prepareCalled, 1u);
  XCTAssertEqual(self.teardownCalled, 1u);
}

- (void)testFailInPrepare
{
  FBFutureContextManager<NSNumber *> *manager = self.manager;
  self.failPrepare = YES;
  FBFuture *future0 = [[manager
    utilizeWithPurpose:@"A Test"]
    onQueue:self.queue pop:^(id result) {
      return [FBFuture futureWithResult:@0];
    }];

  NSError *error = nil;
  id value = [future0 awaitWithTimeout:1 error:&error];
  XCTAssertNotNil(error);

  XCTAssertEqual(self.prepareCalled, 1u);
  XCTAssertEqual(self.teardownCalled, 0u);

  self.failPrepare = NO;
  FBFuture *future1 = [[manager
    utilizeWithPurpose:@"A Test"]
    onQueue:self.queue pop:^(id result) {
      return [FBFuture futureWithResult:@1];
    }];
  error = nil;
  value = [future1 awaitWithTimeout:1 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(value, @1);

  XCTAssertEqual(self.prepareCalled, 2u);
  XCTAssertEqual(self.teardownCalled, 1u);
}

- (void)testConcurrentAquireWithOneFailInPrepare
{
  FBFutureContextManager<NSNumber *> *manager = self.manager;
  dispatch_queue_t concurrent = dispatch_queue_create("com.facebook.fbcontrolcore.tests.future_context.concurrent", DISPATCH_QUEUE_CONCURRENT);
  FBMutableFuture *future0 = FBMutableFuture.future;
  FBMutableFuture *future1 = FBMutableFuture.future;
  FBMutableFuture *future2 = FBMutableFuture.future;

  self.failPrepare = YES;
  self.resetFailPrepare = YES;
  dispatch_async(concurrent, ^{
    FBFuture *inner = [[manager
      utilizeWithPurpose:@"A Test 1"]
      onQueue:self.queue pop:^(id result) {
       return [FBFuture futureWithResult:@0];
      }];
    [future0 resolveFromFuture:inner];
  });
  dispatch_async(concurrent, ^{
    FBFuture *inner = [[manager
    utilizeWithPurpose:@"A Test 2"]
    onQueue:self.queue pop:^(id result) {
      return [FBFuture futureWithResult:@1];
    }];
    [future1 resolveFromFuture:inner];
  });
  dispatch_async(concurrent, ^{
    FBFuture *inner = [[manager
      utilizeWithPurpose:@"A Test 3"]
      onQueue:self.queue pop:^(id result) {
        return [FBFuture futureWithResult:@2];
      }];
    [future2 resolveFromFuture:inner];
  });

  NSMutableArray<NSNumber *> *values = [NSMutableArray array];
  NSMutableArray<NSError *> *errors = [NSMutableArray array];

  for (FBFuture *future in @[future0, future1, future2]) {
    NSNumber *value = nil;
    NSError *error = nil;
    value = [future awaitWithTimeout:1 error:&error];
    if (value) {
      [values addObject:value];
    }
    if (error) {
      [errors addObject:error];
    }
  }

  XCTAssertEqual(values.count, 2u);
  XCTAssertEqual(errors.count, 1u);

  XCTAssertEqual(self.prepareCalled, 2u);
  XCTAssertEqual(self.teardownCalled, 1u);
}

- (void)testImmediateAquireAndRelease
{
  FBFutureContextManager<NSNumber *> *manager = self.manager;

  NSError *error = nil;
  NSNumber *context = [manager utilizeNowWithPurpose:@"A Test" error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(context, @0);

  BOOL success = [manager returnNowWithPurpose:@"A Test" error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

- (NSString *)contextName
{
  return @"A Test";
}

- (FBFuture<id> *)prepare:(id<FBControlCoreLogger>)logger
{
  self.prepareCalled++;
  if (self.failPrepare) {
    if (self.resetFailPrepare) {
      self.failPrepare = NO;
    }
    return [[FBControlCoreError describe:@"Error in prepare"] failFuture];
  }
  else {
    return [FBFuture futureWithResult:@0];
  }
}

- (FBFuture<NSNull *> *)teardown:(id)context logger:(id<FBControlCoreLogger>)logger
{
  self.teardownCalled++;
  return FBFuture.empty;
}

@end

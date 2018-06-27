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

@interface FBFutureContextManagerTests : XCTestCase <FBFutureContextManagerDelegate>

@property (nonatomic, strong, readwrite) dispatch_queue_t queue;
@property (nonatomic, assign, readwrite) NSUInteger prepareCalled;
@property (nonatomic, assign, readwrite) NSUInteger teardownCalled;

@end

@implementation FBFutureContextManagerTests

- (void)setUp
{
  self.queue = dispatch_queue_create("com.facebook.fbcontrolcore.tests.future_context", DISPATCH_QUEUE_SERIAL);
  self.prepareCalled = 0;
  self.teardownCalled = 0;
}

- (FBFutureContextManager<NSNumber *, NSString *> *)manager
{
  id<FBControlCoreLogger> logger = [FBControlCoreGlobalConfiguration.defaultLogger withName:@"manager_test"];
  return [FBFutureContextManager managerWithQueue:self.queue delegate:self logger:logger];
}

- (void)testSingleAquire
{
  FBFuture *future = [[self.manager
    utilizeWithPurpose:@"A Test"]
    onQueue:self.queue fmap:^(id result) {
      return [FBFuture futureWithResult:@123];
    }];

  NSError *error = nil;
  id value = [future awaitWithTimeout:1 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(value, @123);

  XCTAssertEqual(self.prepareCalled, 1);
  XCTAssertEqual(self.teardownCalled, 1);
}

- (void)testConcurrentAquireOnlyPreparesOnce
{
  FBFutureContextManager<NSNumber *, NSString *> *manager = self.manager;
  dispatch_queue_t concurrent = dispatch_queue_create("com.facebook.fbcontrolcore.tests.future_context.concurrent", DISPATCH_QUEUE_CONCURRENT);
  FBMutableFuture *future0 = FBMutableFuture.future;
  FBMutableFuture *future1 = FBMutableFuture.future;
  FBMutableFuture *future2 = FBMutableFuture.future;

  dispatch_async(concurrent, ^{
    FBFuture *inner = [[manager
      utilizeWithPurpose:@"A Test"]
      onQueue:self.queue fmap:^(id result) {
        return [FBFuture futureWithResult:@0];
      }];
    [future0 resolveFromFuture:inner];
  });
  dispatch_async(concurrent, ^{
    FBFuture *inner = [[manager
      utilizeWithPurpose:@"A Test"]
      onQueue:self.queue fmap:^(id result) {
        return [FBFuture futureWithResult:@1];
      }];
    [future1 resolveFromFuture:inner];
  });
  dispatch_async(concurrent, ^{
    FBFuture *inner = [[manager
      utilizeWithPurpose:@"A Test"]
      onQueue:self.queue fmap:^(id result) {
        return [FBFuture futureWithResult:@2];
      }];
    [future2 resolveFromFuture:inner];
  });

  NSError *error = nil;
  id value = [[FBFuture futureWithFutures:@[future0, future1, future2]] awaitWithTimeout:1 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(value, (@[@0, @1, @2]));

  XCTAssertEqual(self.prepareCalled, 1);
  XCTAssertEqual(self.teardownCalled, 1);
}

- (NSString *)contextName
{
  return @"A Test";
}

- (FBFuture<id> *)prepare:(id<FBControlCoreLogger>)logger
{
  self.prepareCalled++;
  return [FBFuture futureWithResult:@0];
}

- (FBFuture<NSNull *> *)teardown:(id)context logger:(id<FBControlCoreLogger>)logger
{
  XCTAssertEqualObjects(context, @0);
  self.teardownCalled++;
  return [FBFuture futureWithResult:NSNull.null];
}

@end

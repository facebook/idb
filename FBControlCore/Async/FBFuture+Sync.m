/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFuture+Sync.h"

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"
#import "FBFuture.h"

static id ExtractResult(FBFuture *future, NSTimeInterval timeout, BOOL completed, NSError **error)
{
  if (!completed) {
    return [[FBControlCoreError
      describeFormat:@"Timed out waiting for future %@ in %f seconds", future, timeout]
      fail:error];
  }
  if (future.error) {
    if (error) {
      *error = future.error;
    }
    return nil;
  }
  if (future.state == FBFutureStateCancelled) {
    return [[FBControlCoreError
      describeFormat:@"Future %@ was cancelled", future]
      fail:error];
  }
  return future.result;
}

@implementation NSRunLoop (FBControlCore)

static NSString *const KeyIsAwaiting = @"FBCONTROLCORE_IS_AWAITING";

+ (void)updateRunLoopIsAwaiting:(BOOL)spinning
{
  NSMutableDictionary *threadLocals = NSThread.currentThread.threadDictionary;
  BOOL spinningRecursively = spinning && [threadLocals[KeyIsAwaiting] boolValue];
  if (spinningRecursively) {
    id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
    [logger logFormat:@"Awaiting Future Recursively %@", [FBCollectionInformation oneLineDescriptionFromArray:NSThread.callStackSymbols]];
  }
  threadLocals[KeyIsAwaiting] = @(spinning);
}

- (BOOL)spinRunLoopWithTimeout:(NSTimeInterval)timeout untilTrue:( BOOL (^)(void) )untilTrue
{
  NSDate *date = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while (!untilTrue()) {
    @autoreleasepool {
      if (timeout > 0 && [date timeIntervalSinceNow] < 0) {
        return NO;
      }
      // Wait for 100ms
      [self runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
  }
  return YES;
}

- (id)spinRunLoopWithTimeout:(NSTimeInterval)timeout untilExists:( id (^)(void) )untilExists
{
  __block id value = nil;
  BOOL success = [self spinRunLoopWithTimeout:timeout untilTrue:^ BOOL {
    value = untilExists();
    return value != nil;
  }];
  if (!success) {
    return nil;
  }
  return value;
}

- (nullable id)awaitCompletionOfFuture:(FBFuture *)future timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  [NSRunLoop updateRunLoopIsAwaiting:YES];
  BOOL completed = [self spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    return future.hasCompleted;
  }];
  [NSRunLoop updateRunLoopIsAwaiting:NO];
  return ExtractResult(future, timeout, completed, error);
}

@end

static NSTimeInterval const ForeverTimeout = DBL_MAX;

static dispatch_queue_t blockQueue()
{
  return dispatch_queue_create("com.facebook.fbfuture.block", DISPATCH_QUEUE_SERIAL);
}

@implementation FBFuture (NSRunLoop)

- (nullable id)await:(NSError **)error
{
  return [self awaitWithTimeout:ForeverTimeout error:error];
}

- (nullable id)awaitWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return [NSRunLoop.currentRunLoop awaitCompletionOfFuture:self timeout:timeout error:error];
}

- (BOOL)succeeds:(NSError **)error
{
  return [self onQueue:blockQueue() timeout:DISPATCH_TIME_FOREVER succeeds:error];
}

- (BOOL)onQueue:(dispatch_queue_t)queue timeout:(dispatch_time_t)timeout succeeds:(NSError **)error
{
  id value = [self onQueue:queue timeout:timeout block:error];
  if (!value) {
    return NO;
  }
  return YES;
}

- (nullable id)block:(NSError **)error
{
  return [self onQueue:blockQueue() timeout:DISPATCH_TIME_FOREVER block:error];
}

- (nullable id)onQueue:(dispatch_queue_t)queue timeout:(dispatch_time_t)timeout block:(NSError **)error
{
  dispatch_group_t group = dispatch_group_create();
  dispatch_group_enter(group);
  [self onQueue:queue notifyOfCompletion:^(FBFuture *future) {
    dispatch_group_leave(group);
  }];
  BOOL completed = dispatch_group_wait(group, timeout) == 0;
  return ExtractResult(self, timeout, completed, error);
}

@end

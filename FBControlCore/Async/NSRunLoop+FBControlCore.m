/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NSRunLoop+FBControlCore.h"

#import <libkern/OSAtomic.h>
#import <objc/runtime.h>

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"
#import "FBFuture.h"

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

- (BOOL)spinRunLoopWithTimeout:(NSTimeInterval)timeout notifiedBy:(dispatch_group_t)group onQueue:(dispatch_queue_t)queue
{
  __block volatile uint32_t didFinish = 0;
  dispatch_group_notify(group, queue, ^{
    OSAtomicOr32Barrier(1, &didFinish);
  });

  return [self spinRunLoopWithTimeout:timeout untilTrue:^ BOOL {
    return didFinish == 1;
  }];
}

- (nullable id)awaitCompletionOfFuture:(FBFuture *)future timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  [NSRunLoop updateRunLoopIsAwaiting:YES];
  BOOL completed = [self spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    return future.hasCompleted;
  }];
  [NSRunLoop updateRunLoopIsAwaiting:NO];
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

@end

@implementation FBFuture (NSRunLoop)

- (nullable id)await:(NSError **)error
{
  return [self awaitWithTimeout:DBL_MAX error:error];
}

- (nullable id)awaitWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return [NSRunLoop.currentRunLoop awaitCompletionOfFuture:self timeout:timeout error:error];
}

@end

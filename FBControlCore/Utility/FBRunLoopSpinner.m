/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBRunLoopSpinner.h"

#import <libkern/OSAtomic.h>
#import <objc/runtime.h>

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"
#import "FBFuture.h"

@interface FBRunLoopSpinner ()
@property (nonatomic, copy) NSString *timeoutErrorMessage;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, copy) NSString *reminderMessage;
@property (nonatomic, assign) NSTimeInterval reminderInterval;
@end

@implementation FBRunLoopSpinner

+ (id)spinUntilBlockFinished:(id (^)(void))block
{
  __block volatile uint32_t didFinish = 0;
  __block id returnObject;
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    returnObject = block();
    OSAtomicOr32Barrier(1, &didFinish);
  });
  while (!didFinish) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
  }
  return returnObject;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _timeout = 60;
    _reminderInterval = 5;
  }
  return self;
}

- (instancetype)reminderMessage:(NSString *)reminderMessage
{
  self.reminderMessage = reminderMessage;
  return self;
}

- (instancetype)reminderInterval:(NSTimeInterval)reminderInterval
{
  self.reminderInterval = reminderInterval;
  return self;
}

- (instancetype)timeoutErrorMessage:(NSString *)timeoutErrorMessage
{
  self.timeoutErrorMessage = timeoutErrorMessage;
  return self;
}

- (instancetype)timeout:(NSTimeInterval)timeout
{
  self.timeout = timeout;
  return self;
}

- (BOOL)spinUntilTrue:(BOOL (^)(void))untilTrue
{
  return [self spinUntilTrue:untilTrue error:nil];
}

- (BOOL)spinUntilTrue:(BOOL (^)(void))untilTrue error:(NSError **)error
{
  NSDate *messageTimeout = [NSDate dateWithTimeIntervalSinceNow:self.reminderInterval];
  NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:self.timeout];
  while (!untilTrue()) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    if (timeoutDate.timeIntervalSinceNow < 0) {
      return [[FBControlCoreError
        describe:(self.timeoutErrorMessage ?: @"FBRunLoopSpinner timeout")]
        failBool:error];
    }
    if (self.reminderMessage && messageTimeout.timeIntervalSinceNow < 0) {
      messageTimeout = [NSDate dateWithTimeIntervalSinceNow:self.reminderInterval];
    }
  }
  return YES;
}

@end

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

- (nullable id)awaitCompletionOfFuture:(FBFuture *)future timeout:(NSTimeInterval)timeout didTimeout:(BOOL *)didTimeout error:(NSError **)error
{
  [NSRunLoop updateRunLoopIsAwaiting:YES];
  BOOL completed = [self spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    return future.hasCompleted;
  }];
  [NSRunLoop updateRunLoopIsAwaiting:NO];
  if (!completed) {
    if (didTimeout) {
      *didTimeout = YES;
    }
    return [[FBControlCoreError
      describeFormat:@"Timed out waiting for future %@ in %f seconds", future, timeout]
      fail:error];
  }
  if (didTimeout) {
    *didTimeout = NO;
  }
  if (future.error) {
    if (error) {
      *error = future.error;
    }
    return nil;
  }
  return future.result;
}

- (nullable id)awaitCompletionOfFuture:(FBFuture *)future timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  BOOL didTimeout = NO;
  return [self awaitCompletionOfFuture:future timeout:timeout didTimeout:&didTimeout error:error];
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

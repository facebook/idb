/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFutureContextManager.h"

#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBFuture.h"

@interface FBFutureContextManager ()

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, weak, readonly) id<FBFutureContextManagerDelegate> delegate;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@property (nonatomic, strong, readonly) NSMutableArray<FBMutableFuture<NSNull *> *> *pending;
@property (nonatomic, strong, nullable, readwrite) FBFuture<NSNull *> *teardownTimeout;
@property (nonatomic, strong, nullable, readwrite) FBFuture<NSNull *> *current;
@property (nonatomic, strong, readwrite) id existingContext;


@end

@implementation FBFutureContextManager

#pragma mark Initializers

+ (instancetype)managerWithQueue:(dispatch_queue_t)queue delegate:(id<FBFutureContextManagerDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithQueue:queue delegate:delegate logger:logger];
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue delegate:(id<FBFutureContextManagerDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _queue = queue;
  _delegate = delegate;
  _logger = logger;

  _pending = [NSMutableArray array];
  _existingContext = nil;

  return self;
}

#pragma mark Public Methods

- (FBFutureContext<id> *)utilizeWithPurpose:(NSString *)purpose
{
  id<FBControlCoreLogger> logger = [self loggerWithPurpose:purpose];
  return [[[[self
    resourceNoLongerInUseWithLogger:logger]
    onQueue:self.queue fmap:^ FBFuture<id> * (id _){
      [self cancelTimer:logger];
      id existingContext = self.existingContext;
      if (existingContext) {
       [logger logFormat:@"Re-Using existing context %@", existingContext];
       return [FBFuture futureWithResult:self.existingContext];
      }
      [logger log:@"No active context, preparing..."];
      return [self.delegate prepare:logger];
    }]
    onQueue:self.queue map:^(id context) {
      self.existingContext = context;
      return context;
    }]
    onQueue:self.queue contextualTeardown:^(id _) {
      NSUInteger remainingConsumers = [self popQueue];
      if (remainingConsumers == 0) {
        id existingContext = self.existingContext;
        NSAssert(existingContext, @"Expected a context preserved");
        NSNumber *poolTimeout = self.delegate.contextPoolTimeout;
        if (poolTimeout) {
          NSTimeInterval timeout = poolTimeout.doubleValue;
          [logger logFormat:@"No more consumers, but pooling the context, will wait for %f seconds of inactivity before tearing down", timeout];
          [self teardownInFuture:timeout logger:logger];
        } else {
          [logger log:@"No more consumers, no timeout tearing down context now"];
          [self teardownNow:logger];
        }
      } else {
        [logger logFormat:@"%lu More consumers waiting, not tearing down", remainingConsumers];
      }
    }];
}

- (id)utilizeNowWithPurpose:(NSString *)purpose error:(NSError **)error
{
  if (self.pending.count > 0 || self.current || self.existingContext) {
    return [[FBControlCoreError
      describeFormat:@"Could not utilize context synchronously for %@ it is already in use", purpose]
      fail:error];
  }
  id<FBControlCoreLogger> logger = [self loggerWithPurpose:purpose];
  FBFuture<id> *prepare = [self.delegate prepare:logger];
  if (!prepare.result) {
    return [[FBControlCoreError
      describeFormat:@"Could not extract prepare synchronously in %@", prepare]
      fail:error];
  }
  self.existingContext = prepare.result;
  return self.existingContext;
}

- (BOOL)returnNowWithPurpose:(NSString *)purpose error:(NSError **)error
{
  id existingContext = self.existingContext;
  if (!existingContext) {
    return [[FBControlCoreError
      describeFormat:@"Could not return context for '%@' as none exists", purpose]
      failBool:error];
  }
  id<FBControlCoreLogger> logger = [self loggerWithPurpose:purpose];
  FBFuture<NSNull *> *teardown = [self.delegate teardown:existingContext logger:logger];
  if (!teardown.result) {
    return [[FBControlCoreError
      describeFormat:@"Could not return context synchronously in %@", teardown]
      failBool:error];
  }
  self.existingContext = nil;
  return YES;
}

#pragma mark Private

- (id<FBControlCoreLogger>)loggerWithPurpose:(NSString *)purpose
{
  return [self.logger withName:[NSString stringWithFormat:@"%@_%@", self.delegate.contextName, purpose]];
}

- (FBFuture<NSNull *> *)resourceNoLongerInUseWithLogger:(id<FBControlCoreLogger>)logger
{
  return [FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSNull *> * {
      if (self.current) {
        [logger logFormat:@"Context '%@' currently in use, waiting for it to be available", self.delegate.contextName];
        FBMutableFuture<NSNull *> *deviceAvailable = FBMutableFuture.future;
        [self.pending addObject:deviceAvailable];
        return deviceAvailable;
      }
      if (self.existingContext) {
        [logger logFormat:@"No user of context '%@' but we don't need to re-aquire it", self.delegate.contextName];
        self.current = [FBFuture futureWithResult:NSNull.null];
        return self.current;
      }
      [logger logFormat:@"Context '%@' not in use, time to aquire it", self.delegate.contextName];
      self.current = [FBFuture futureWithResult:NSNull.null];
      return self.current;
    }];
}

- (NSUInteger)popQueue
{
  NSUInteger pendingConsumers = self.pending.count;
  if (pendingConsumers == 0) {
    self.current = nil;
    return 0;
  }
  FBMutableFuture<NSNull *> *future = [self.pending lastObject];
  [self.pending removeLastObject];
  [future resolveWithResult:NSNull.null];
  self.current = future;
  return pendingConsumers;
}

- (void)teardownInFuture:(NSTimeInterval)timeout logger:(id<FBControlCoreLogger>)logger
{
  [self cancelTimer:logger];

  __weak typeof(self) weakSelf = self;
  self.teardownTimeout = [[FBFuture
    futureWithDelay:timeout future:[FBFuture futureWithResult:NSNull.null]]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      if (!future.result) {
        return;
      }
      if (weakSelf.current) {
        [logger logFormat:@"Not tearing down context after %f seconds as we have an existing consumer", timeout];
      } else {
        [logger logFormat:@"No-one else wants the context, tearing it down"];
        [weakSelf teardownNow:logger];
      }
    }];
}

- (void)cancelTimer:(id<FBControlCoreLogger>)logger
{
  if (self.teardownTimeout) {
    [logger logFormat:@"Cancelling timer for old timeout"];
    [self.teardownTimeout cancel];
    self.teardownTimeout = nil;
  }
}

- (void)teardownNow:(id<FBControlCoreLogger>)logger
{
  id existingContext = self.existingContext;
  if (!existingContext) {
    [logger log:@"Nothing to teardown"];
    return;
  }
  [logger logFormat:@"Tearing down context %@ now", existingContext];
  [self.delegate teardown:existingContext logger:logger];
  self.existingContext = nil;
}

@end

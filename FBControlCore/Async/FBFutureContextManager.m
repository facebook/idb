/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFutureContextManager.h"

#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBFuture.h"

@interface FBFutureContextManager ()

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, weak, readonly) id<FBFutureContextManagerDelegate> delegate;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@property (nonatomic, strong, readonly) NSMutableArray<NSUUID *> *pendingOrdering;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSUUID *, FBMutableFuture<NSUUID *> *> *pending;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSUUID *, FBFuture<NSUUID *> *> *using;
@property (nonatomic, strong, nullable, readwrite) FBFuture<NSNull *> *teardownTimeout;
@property (nonatomic, strong, nullable, readwrite) FBFuture<id> *context;

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

  _pendingOrdering = [NSMutableArray array];
  _pending = [NSMutableDictionary dictionary];
  _using = [NSMutableDictionary dictionary];
  _context = nil;

  return self;
}

#pragma mark Public Methods

- (FBFutureContext<id> *)utilizeWithPurpose:(NSString *)purpose
{
  id<FBControlCoreLogger> logger = [self loggerWithPurpose:purpose];
  NSUUID *uuid = NSUUID.UUID;
  return [[[[self
    resourceAvailableForUseWithUUID:uuid logger:logger]
    onQueue:self.queue fmap:^ FBFuture<id> * (id _){
      [self cancelTimer:logger];
      FBFuture<id> *context = self.context;
      if (context.hasCompleted) {
        [logger logFormat:@"Re-Using existing context %@", context.result];
        return [FBFuture futureWithResult:context.result];
      }
      if (context) {
        [logger logFormat:@"Re-Using preparing context %@", context];
        return context;
      }
      [logger log:@"No active context, preparing..."];
      context = [self.delegate prepare:logger];
      self.context = context;
      return context;
    }]
    onQueue:self.queue handleError:^ FBFuture *(NSError *error) {
      self.context = nil;
      [self popPending:uuid];
      return [FBFuture futureWithError:error];
    }]
    onQueue:self.queue contextualTeardown:^(id _, FBFutureState __) {
      NSUInteger remainingConsumers = [self popPending:uuid];
      if (remainingConsumers == 0) {
        FBFuture<id> *context = self.context;
        NSAssert(context, @"Expected a context preserved");
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
        [logger logFormat:@"%lu More consumers waiting or running, not tearing down", remainingConsumers];
      }
      return FBFuture.empty;
    }];
}

- (id)utilizeNowWithPurpose:(NSString *)purpose error:(NSError **)error
{
  if (self.pending.count > 0 || self.using.count > 0 || self.context) {
    return [[FBControlCoreError
      describeFormat:@"Could not utilize context synchronously for %@ it is already in use", purpose]
      fail:error];
  }
  id<FBControlCoreLogger> logger = [self loggerWithPurpose:purpose];
  FBFuture<id> *context = [self.delegate prepare:logger];
  if (!context.result) {
    return [[FBControlCoreError
      describeFormat:@"Could not extract prepare synchronously in %@", context]
      fail:error];
  }
  self.context = context;
  return context.result;
}

- (BOOL)returnNowWithPurpose:(NSString *)purpose error:(NSError **)error
{
  FBFuture<id> *context = self.context;
  if (!context) {
    return [[FBControlCoreError
      describeFormat:@"Could not return context for '%@' as none exists", purpose]
      failBool:error];
  }
  id<FBControlCoreLogger> logger = [self loggerWithPurpose:purpose];
  FBFuture<NSNull *> *teardown = [self.delegate teardown:context.result logger:logger];
  if (!teardown.result) {
    return [[FBControlCoreError
      describeFormat:@"Could not return context synchronously in %@", teardown]
      failBool:error];
  }
  self.context = nil;
  return YES;
}

#pragma mark Private

- (id<FBControlCoreLogger>)loggerWithPurpose:(NSString *)purpose
{
  return [self.logger withName:[NSString stringWithFormat:@"%@_%@", self.delegate.contextName, purpose]];
}

- (FBFuture<NSUUID *> *)resourceAvailableForUseWithUUID:(NSUUID *)uuid logger:(id<FBControlCoreLogger>)logger
{
  return [FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSUUID *> * {
      if (self.using.count > 0) {
        if (self.delegate.isContextSharable) {
          [logger logFormat:@"Context '%@' in use, but it can be shared", self.delegate.contextName];
          return [self immedateResourceAvailable:uuid];
        } else {
          [logger logFormat:@"Context '%@' currently in use, waiting for it to be available", self.delegate.contextName];
          return [self pushPending:uuid];
        }
      }
      if (self.context) {
        [logger logFormat:@"No user of context '%@' but we don't need to re-aquire it", self.delegate.contextName];
        return [self immedateResourceAvailable:uuid];
      }
      [logger logFormat:@"Context '%@' not in use, time to aquire it", self.delegate.contextName];
      return [self immedateResourceAvailable:uuid];
    }];
}

- (FBFuture<NSUUID *> *)immedateResourceAvailable:(NSUUID *)uuid
{
  FBFuture<NSUUID *> *immediate = [FBFuture futureWithResult:uuid];
  self.using[uuid] = immediate;
  return immediate;
}

- (FBFuture<NSUUID *> *)pushPending:(NSUUID *)uuid
{
  FBMutableFuture<NSUUID *> *deviceAvailable = FBMutableFuture.future;
  self.pending[uuid] = deviceAvailable;
  [self.pendingOrdering addObject:uuid];
  return deviceAvailable;
}

- (NSUInteger)popPending:(NSUUID *)finished
{
  // Remove the current
  NSParameterAssert(self.using[finished]);
  [self.using removeObjectForKey:finished];

  // If we have no pending, just return what we have (if any) in flight.
  if (self.pendingOrdering.count == 0) {
    return self.using.count;
  }

  // Otherwise we pull the pending to the front and start it off.
  NSUUID *next = [self.pendingOrdering lastObject];
  [self.pendingOrdering removeLastObject];

  FBMutableFuture<NSUUID *> *future = self.pending[next];
  [self.pending removeObjectForKey:next];
  NSParameterAssert(future);
  [future resolveWithResult:next];

  self.using[next] = future;
  return self.pendingOrdering.count + self.using.count;
}

- (void)teardownInFuture:(NSTimeInterval)timeout logger:(id<FBControlCoreLogger>)logger
{
  [self cancelTimer:logger];

  __weak typeof(self) weakSelf = self;
  self.teardownTimeout = [[FBFuture
    futureWithDelay:timeout future:FBFuture.empty]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      if (!future.result) {
        return;
      }
      if (weakSelf.using.count > 0) {
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
  id result = self.context.result;
  if (!result) {
    [logger log:@"Nothing to teardown"];
    return;
  }
  [logger logFormat:@"Tearing down context %@ now", result];
  [self.delegate teardown:result logger:logger];
  self.context = nil;
}

@end

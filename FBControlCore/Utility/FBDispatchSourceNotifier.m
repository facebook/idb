/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDispatchSourceNotifier.h"

@implementation FBDispatchSourceNotifier

#pragma mark Initializers

+ (FBFuture<NSNumber *> *)processTerminationFutureNotifierForProcessIdentifier:(pid_t)processIdentifier
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.dispatch_notifier", DISPATCH_QUEUE_SERIAL);
  dispatch_source_t source = dispatch_source_create(
    DISPATCH_SOURCE_TYPE_PROC,
    (unsigned long) processIdentifier,
    DISPATCH_PROC_EXIT,
    queue
  );

  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;
  [future onQueue:queue respondToCancellation:^ FBFuture<NSNull *> * {
    dispatch_source_cancel(source);
    return FBFuture.empty;
  }];
  dispatch_source_set_event_handler(source, ^(){
    [future resolveWithResult:@(processIdentifier)];
    dispatch_source_cancel(source);
  });
  dispatch_resume(source);

  return future;
}

+ (instancetype)processTerminationNotifierForProcessIdentifier:(pid_t)processIdentifier queue:(dispatch_queue_t)queue handler:(void (^)(FBDispatchSourceNotifier *))handler
{
  dispatch_source_t dispatchSource = dispatch_source_create(
    DISPATCH_SOURCE_TYPE_PROC,
    (unsigned long) processIdentifier,
    DISPATCH_PROC_EXIT,
    queue
  );
  return [[self alloc] initWithDispatchSource:dispatchSource handler:handler];
}

+ (instancetype)timerNotifierNotifierWithTimeInterval:(uint64_t)timeInterval queue:(dispatch_queue_t)queue handler:(void (^)(FBDispatchSourceNotifier *))handler
{
  dispatch_source_t dispatchSource = dispatch_source_create(
    DISPATCH_SOURCE_TYPE_TIMER,
    0,
    0,
    queue
  );
  dispatch_source_set_timer(dispatchSource, dispatch_time(DISPATCH_TIME_NOW, (int64_t) timeInterval), timeInterval, 0);
  return [[self alloc] initWithDispatchSource:dispatchSource handler:handler];
}

- (instancetype)initWithDispatchSource:(dispatch_source_t)dispatchSource handler:(void (^)(FBDispatchSourceNotifier *))handler
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _dispatchSource = dispatchSource;
  __weak typeof(self) weakSelf = self;
  dispatch_source_set_event_handler(dispatchSource, ^(){
    __strong typeof(self) strongSelf = weakSelf;
    handler(strongSelf);
  });
  dispatch_resume(dispatchSource);
  return self;
}

#pragma mark Public

- (void)terminate
{
  if (self.dispatchSource) {
    dispatch_source_cancel(self.dispatchSource);
    _dispatchSource = nil;
  }
}

- (void)dealloc
{
  [self terminate];
}

@end

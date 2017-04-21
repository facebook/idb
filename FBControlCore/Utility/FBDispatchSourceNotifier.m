/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDispatchSourceNotifier.h"

FBTerminationHandleType const FBTerminationHandleTypeDispatchSource = @"DispatchSource";

@implementation FBDispatchSourceNotifier

+ (instancetype)processTerminationNotifierForProcessIdentifier:(pid_t)processIdentifier handler:(void (^)(FBDispatchSourceNotifier *))handler
{
  dispatch_source_t dispatchSource = dispatch_source_create(
    DISPATCH_SOURCE_TYPE_PROC,
    (unsigned long) processIdentifier,
    DISPATCH_PROC_EXIT,
    dispatch_get_main_queue()
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
  dispatch_source_set_timer(dispatchSource, DISPATCH_TIME_NOW, timeInterval, 0);
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

- (void)terminate
{
  if (self.dispatchSource) {
    dispatch_source_cancel(self.dispatchSource);
    _dispatchSource = nil;
  }
}

- (FBTerminationHandleType)type
{
  return FBTerminationHandleTypeDispatchSource;
}

- (void)dealloc
{
  [self terminate];
}

@end

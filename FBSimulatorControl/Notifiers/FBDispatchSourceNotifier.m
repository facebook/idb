/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDispatchSourceNotifier.h"

@interface FBDispatchSourceNotifier ()

@property (nonatomic, strong) dispatch_source_t dispatchSource;

@end

@implementation FBDispatchSourceNotifier

+ (instancetype)processTerminationNotifierForProcessIdentifier:(pid_t)processIdentifier handler:(void (^)(FBDispatchSourceNotifier *))handler
{
  dispatch_source_t dispatchSource = dispatch_source_create(
    DISPATCH_SOURCE_TYPE_PROC,
    (unsigned long) processIdentifier,
    DISPATCH_PROC_EXIT,
    DISPATCH_TARGET_QUEUE_DEFAULT
  );
  return [[self alloc] initWithDispatchSource:dispatchSource handler:handler];
}

- (instancetype)initWithDispatchSource:(dispatch_source_t)dispatchSource handler:(void (^)(FBDispatchSourceNotifier *))handler
{
  self = [super init];
  if (!self) {
    return nil;
  }

  self.dispatchSource = dispatchSource;
  __weak typeof(self) weakSelf = self;
  dispatch_source_set_event_handler(dispatchSource, ^(){
    __strong typeof(self) strongSelf = weakSelf;
    dispatch_async(dispatch_get_main_queue(), ^{
      handler(strongSelf);
    });
  });
  dispatch_resume(dispatchSource);
  return self;
}

- (void)terminate
{
  if (self.dispatchSource) {
    dispatch_source_cancel(self.dispatchSource);
    self.dispatchSource = nil;
  }
}

- (void)dealloc
{
  [self terminate];
}

@end

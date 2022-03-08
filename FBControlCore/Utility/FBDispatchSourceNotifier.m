/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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

@end

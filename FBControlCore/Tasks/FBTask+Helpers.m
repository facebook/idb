/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTask+Helpers.h"

#import "FBControlCoreError.h"

@implementation FBTask (Helpers)

- (FBFuture<NSNumber *> *)sendSignal:(int)signo backingOfToKillWithTimeout:(NSTimeInterval)timeout
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.task_terminate", DISPATCH_QUEUE_SERIAL);
  FBFuture<NSNumber *> *signal = [self sendSignal:signo];
  FBFuture<NSNumber *> *kill = [[[FBFuture
    futureWithResult:NSNull.null]
    delay:timeout]
    onQueue:queue fmap:^(id _) {
      return [self sendSignal:SIGKILL];
    }];
  return [FBFuture race:@[signal, kill]];
}

@end

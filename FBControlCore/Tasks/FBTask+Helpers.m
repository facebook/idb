/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTask+Helpers.h"

#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"

@implementation FBTask (Helpers)

- (FBFuture<NSNumber *> *)sendSignal:(int)signo backingOffToKillWithTimeout:(NSTimeInterval)timeout logger:(id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.task_terminate", DISPATCH_QUEUE_SERIAL);
  FBFuture<NSNumber *> *signal = [self sendSignal:signo];
  FBFuture<NSNumber *> *kill = [[[FBFuture
    futureWithResult:NSNull.null]
    delay:timeout]
    onQueue:queue fmap:^(id _) {
      [logger logFormat:@"Process %d didn't exit after wait for %f seconds for sending signal %d, sending SIGKILL now.", [self processIdentifier], timeout, signo];
      return [self sendSignal:SIGKILL];
    }];
  return [FBFuture race:@[signal, kill]];
}

@end

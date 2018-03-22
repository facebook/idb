/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBTask.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Builds on top of the FBTask API
 */
@interface FBTask (Helpers)

/**
 A mechanism for sending an signal to a task, backing off to a kill.
 If the process does not die before the timeout is hit, a SIGKILL will be sent.

 @param signo the signal number to send.
 @param timeout the timeout to wait before sending a SIGKILL.
 @return a future that resolves when the process has been terminate.
 */
- (FBFuture<NSNumber *> *)sendSignal:(int)signo backingOfToKillWithTimeout:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END

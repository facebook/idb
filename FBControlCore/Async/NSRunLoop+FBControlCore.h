/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Conveniences to aid synchronous waiting on events, whilst not blocking other event sources.
 */
@interface NSRunLoop (FBControlCore)

/**
 Spins the Run Loop until `untilTrue` returns YES or a timeout is reached.

 @oaram timeout the Timeout in Seconds.
 @param untilTrue the condition to meet.
 @return YES if the condition was met, NO if the timeout was reached first.
 */
- (BOOL)spinRunLoopWithTimeout:(NSTimeInterval)timeout untilTrue:( BOOL (^)(void) )untilTrue;

/**
 Spins the Run Loop until `untilTrue` returns a value, or a timeout is reached.

 @oaram timeout the Timeout in Seconds.
 @param untilExists the mapping to a value.
 @return the return value of untilTrue, or nil if a timeout was reached.
 */
- (nullable id)spinRunLoopWithTimeout:(NSTimeInterval)timeout untilExists:( id (^)(void) )untilExists;

/**
 Spins the Run Loop until the group completes, or a timeout is reached.

 @param timeout the Timeout in Seconds.
 @param group the group to wait on.
 @return YES if the group completed before the timeout, NO otherwise.
 */
- (BOOL)spinRunLoopWithTimeout:(NSTimeInterval)timeout notifiedBy:(dispatch_group_t)group onQueue:(dispatch_queue_t)queue;

@end

/**
 Helpers for awaiting the completion of an FBFuture from a Run Loop.
 */
@interface FBFuture<T> (NSRunLoop)

/**
 Await the Future, with no Timeout.

 @param error an error outparam if the Future resolves with an error.
 @return the the Future's result if successful, nil otherwise.
 */
- (nullable T)await:(NSError **)error;

/**
 Await the Future with the provided timeout.

 @param timeout the timeout in seconds to wait.
 @param error an error outparam if the Future resolves with an error, or the Future is not resolved within the timeout.
 @return the the Future's result if successful, nil otherwise.
 */
- (nullable T)awaitWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

@end

/**
 Helpers for extracting the value from an FBFuture.
 Since FBFuture only exposes callback mounting in it's main interface, this allows callers to wait for a value to appear asynchronously.
 */
@interface FBFuture<T> (Sync)

/**
 Await the Future, with no Timeout.
 This will spin the run loop whilst waiting for the Future to resolve.
 For threads and queues that don't have a Run Loop, one will be created in accordance with +[NSRunLoop currentRunLoop].

 @param error an error outparam if the Future resolves with an error.
 @return the the Future's result if successful, nil otherwise.
 */
- (nullable T)await:(NSError **)error;

/**
 Await the Future with the provided timeout.
 This will spin the run loop whilst waiting for the Future to resolve.
 For threads and queues that don't have a Run Loop, one will be created in accordance with +[NSRunLoop currentRunLoop].

 @param timeout the timeout in seconds to wait.
 @param error an error outparam if the Future resolves with an error, or the Future is not resolved within the timeout.
 @return the the Future's result if successful, nil otherwise.
 */
- (nullable T)awaitWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

/**
 Block until the Future is completed and return whether is succeeded.
 This will use dispatch internally and should *never* be called from the main thread/queue, or any thread/queue that needs to be serviced for the Future to resolve.
 This is useful if the value returned by the future is not significant for the caller, only that it succeeded.

 @param error an error outparam if the Future resolves with an error.
 @return YES if the future completes successfully, NO otherwise.
 */
- (BOOL)succeeds:(NSError **)error;

/**
 Block until the Future is completed and return whether is succeeded.
 This will use dispatch internally and should *never* be called from the main thread/queue, or any thread/queue that needs to be serviced for the Future to resolve.
 This is useful if the value returned by the future is not significant for the caller, only that it succeeded.

 @param error an error outparam if the Future resolves with an error or times out.
 @return YES if the future completes successfully, NO otherwise.
 */
- (BOOL)onQueue:(dispatch_queue_t)queue timeout:(dispatch_time_t)timeout succeeds:(NSError **)error;

/**
 Block until the Future is completed and return the result.
 This will use dispatch internally and should *never* be called from the main thread/queue, or any thread/queue that needs to be serviced for the Future to resolve.

 @param error an error outparam if the Future resolves with an error.
 @return the the Future's result if successful, nil otherwise.
 */
- (nullable T)block:(NSError **)error;

/**
 Block until the Future is completed and return the result.
 This will use dispatch internally and should *never* be called from the main thread/queue, or any thread/queue that needs to be serviced for the Future to resolve.

 @param queue the queue to serialize on.
 @param timeout the timeout in dispatch_time to wait
 @param error an error outparam if the Future resolves with an error or times out.
 @return the the Future's result if successful, nil otherwise.
 */
- (nullable T)onQueue:(dispatch_queue_t)queue timeout:(dispatch_time_t)timeout block:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

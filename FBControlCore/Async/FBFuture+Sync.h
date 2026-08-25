/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

/**
 Helpers for extracting the value from an FBFuture.
 Since FBFuture only exposes callback mounting in it's main interface, this allows callers to wait for a value to appear asynchronously.
 */
@interface FBFuture <T>(Sync)

/**
 Await the Future, with no Timeout.
 This will spin the run loop whilst waiting for the Future to resolve.
 For threads and queues that don't have a Run Loop, one will be created in accordance with +[NSRunLoop currentRunLoop].

 @param error an error outparam if the Future resolves with an error.
 @return the the Future's result if successful, nil otherwise.
 */
- (nullable T)await:(NSError * _Nullable * _Nullable)error;

/**
 Await the Future with the provided timeout.
 This will spin the run loop whilst waiting for the Future to resolve.
 For threads and queues that don't have a Run Loop, one will be created in accordance with +[NSRunLoop currentRunLoop].

 @param timeout the timeout in seconds to wait.
 @param error an error outparam if the Future resolves with an error, or the Future is not resolved within the timeout.
 @return the the Future's result if successful, nil otherwise.
 */
- (nullable T)awaitWithTimeout:(NSTimeInterval)timeout error:(NSError * _Nullable * _Nullable)error;

/**
 Block until the Future is completed and return the result.
 This will use dispatch internally and should *never* be called from the main thread/queue, or any thread/queue that needs to be serviced for the Future to resolve.

 @param error an error outparam if the Future resolves with an error.
 @return the the Future's result if successful, nil otherwise.
 */
- (nullable T)block:(NSError * _Nullable * _Nullable)error;

@end

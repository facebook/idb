/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class DVTiOSDevice;

/**
 A Strategy for waiting on DVTiOSDevice readyness.
 */
@interface FBiOSDeviceReadynessStrategy : NSObject

- (instancetype)init NS_UNAVAILABLE;

/**
 Creates and returns a new Readyness Strategy.

 @param device the DVTDevice to use for the strategy.
 @param queue the queue run the strategy on.
 @return a new Readyness Strategy Instance.
 */
+ (instancetype)strategyWithDVTDevice:(DVTiOSDevice *)device workQueue:(dispatch_queue_t)queue;

/**
 Ensures device supports XPC service debugging and contains a service HUB control channel.

 @param error an error out for any error that occurs.
 @return YES if the device is ready for debugging.
 */
- (BOOL)isReadyForDebuggingWithError:(NSError **)error;

/**
 Awaits for the device to be unlocked.

 @return A future wrapping the device's lock state.
 */
- (FBFuture<NSNull *> *)waitForDevicePasscodeUnlock;

/**
 Awaits for the device to be available.

 @return A future wrapping the device's availability.
 */
- (FBFuture<NSNull *> *)waitForDeviceAvailable;

/**
 Awaits for the device to be ready.

 @return A future wrapping the device's readyness.
 */
- (FBFuture<NSNull *> *)waitForDeviceReady;

/**
 Awaits for the device pre-launch console.

 @return A future wrapping the device's pre-launch console.
 */
- (FBFuture<NSNull *> *)waitForDevicePreLaunchConsole;

/**
 Awaits for the device to be ready for debugging.

 @return A future wrapping the device's debugging state.
 */
- (FBFuture<NSNull *> *)waitForDeviceReadyToDebug;

@end

NS_ASSUME_NONNULL_END

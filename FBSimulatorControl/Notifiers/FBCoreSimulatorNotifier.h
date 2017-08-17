/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBTerminationHandle.h>

@class FBSimulator;
@class FBSimulatorSet;
@class SimDevice;

NS_ASSUME_NONNULL_BEGIN

/**
 The Termination Handle Type.
 */
extern FBTerminationHandleType const FBTerminationHandleTypeCoreSimulatorNotifier;

/**
 A class for wrapping Core Simulator Notifiers in a `FBTerminationHandle`
 */
@interface FBCoreSimulatorNotifier : NSObject <FBTerminationHandle>

/**
 Creates and returns an FBSimDeviceNotifier for the lifecycle events that SimDevice broadcasts.

 @param simDevice the FBSimulator to relay events from.
 @param queue the queue to call the block on.
 @param block the block to call when events are sent from the SimDevice.
 @return an instance of FBSimDeviceNotifier for later termination.
 */
+ (instancetype)notifierForSimDevice:(SimDevice *)simDevice queue:(dispatch_queue_t)queue block:(void (^)(NSDictionary *info))block;

/**
 Creates and returns an FBSimDeviceNotifier for the lifecycle events that SimDeviceSet broadcasts for the provided Set.

 @param set the FBSimulator to relay events from.
 @param queue the queue to call the block on.
 @param block the block to call when events are sent from the SimDevice.
 @return an instance of FBSimDeviceNotifier for later termination.
 */
+ (instancetype)notifierForSet:(FBSimulatorSet *)set queue:(dispatch_queue_t)queue block:(void (^)(NSDictionary *info))block;

@end

NS_ASSUME_NONNULL_END

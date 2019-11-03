/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;
@class FBSimulatorSet;
@class SimDevice;

/**
 A Notifies of Lifecycle events in CoreSimulator.
 */
@interface FBCoreSimulatorNotifier : NSObject

#pragma mark Initializers

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

#pragma mark Public Methods

/**
 Terminates the Notifier.
 */
- (void)terminate;

@end

NS_ASSUME_NONNULL_END

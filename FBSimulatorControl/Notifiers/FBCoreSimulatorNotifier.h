/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBSimulator;
@class FBSimulatorSet;
@class SimDevice;

/**
 A Notifies of Lifecycle events in CoreSimulator.
 */
@interface FBCoreSimulatorNotifier : NSObject

#pragma mark Initializers

/**
 Creates and returns an FBSimDeviceNotifier for the lifecycle events that SimDeviceSet broadcasts for the provided Set.

 @param set the FBSimulator to relay events from.
 @param queue the queue to call the block on.
 @param block the block to call when events are sent from the SimDevice.
 @return an instance of FBSimDeviceNotifier for later termination.
 */
+ (nonnull instancetype)notifierForSet:(nonnull FBSimulatorSet *)set queue:(nonnull dispatch_queue_t)queue block:(nonnull void (^)(NSDictionary<NSString *, id> * _Nonnull info))block;

/**
 Waits for the state to leave the state on the provided SimDevice.

 @param state the state to resolve.
 @param device the SimDevice to resolve state on.
 @return a future that resolves when the state resolves.
 */
+ (nonnull FBFuture<NSNull *> *)resolveLeavesState:(FBiOSTargetState)state forSimDevice:(nonnull SimDevice *)device;

#pragma mark Public Methods

/**
 Terminates the Notifier.
 */
- (void)terminate;

@end

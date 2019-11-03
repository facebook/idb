/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;

/**
 A Strategy for 'Shutting Down' a Simulator.
 */
@interface FBSimulatorShutdownStrategy : NSObject

#pragma mark Initializers

/**
 Create a Strategy for Shutting Down a Simulator.

 @param simulator the simulator to shutdown.
 @return a new Strategy.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator;

#pragma mark Public Methdos

/**
 'Shutting Down' a Simulator can be a little hairier than just calling '-[SimDevice shutdownWithError:]'.
 This method of shutting down takes into account a variety of error states and attempts to recover from them.

 Note that 'Shutting Down' a Simulator is different to 'terminating' or 'killing':
 - Killing a Simulator will kill the Simulator.app process.
 - Killing the Simulator.app process will soon-after get the SimDevice into a 'Shutdown' state in CoreSimulator.
 - This will take a number of seconds and represents an inconsistent state for the Simulator.
 - Calling Shutdown on a Simulator without terminating the Simulator.app process first will result in a 'Zombie' Simulator.
 - A 'Zombie' Simulator.app is a Simulator that isn't backed by a running SimDevice in CoreSimulator.

 Therefore this method should be called if:
 - A Simulator has no corresponding 'Simulator.app'. This is the case if `-[SimDevice bootWithOptions:error]` has been called directly.
 - After Simulator's corresponding 'Simulator.app' has been killed.

 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)shutdown;

@end

NS_ASSUME_NONNULL_END

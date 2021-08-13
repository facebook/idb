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
@class FBSimulatorSet;

/**
 A class for terminating Simulators.
 */
@interface FBSimulatorTerminationStrategy : NSObject

#pragma mark Initializers

/**
 Creates a FBSimulatorTerminationStrategy using the provided configuration.

 @param set the Simulator Set to log.
 @return a configured FBSimulatorTerminationStrategy instance.
 */
+ (instancetype)strategyForSet:(FBSimulatorSet *)set;

#pragma mark Public Methods

/**
 Kills the provided Simulators.
 This call ensures that all of the Simulators:
 1) Have any relevant Simulator.app process killed (if any applicable Simulator.app process is found).
 2) Have the appropriate SimDevice state at 'Shutdown'

 @param simulators the Simulators to Kill.
 @return A future that wraps an array of the Simulators that were killed.
 */
- (FBFuture<NSArray<FBSimulator *> *> *)killSimulators:(NSArray<FBSimulator *> *)simulators;

@end

NS_ASSUME_NONNULL_END

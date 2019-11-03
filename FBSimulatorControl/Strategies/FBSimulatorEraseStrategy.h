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
 A Strategy for Erasing Simulator Contents.
 */
@interface FBSimulatorEraseStrategy : NSObject

#pragma mark Initializers

/**
 Creates a FBSimulatorEraseStrategy.

 @param set the Simulator Set to create the strategy for,
 @return a configured FBSimulatorTerminationStrategy instance.
 */
+ (instancetype)strategyForSet:(FBSimulatorSet *)set;

#pragma mark Public

/**
 Erases the provided Simulators, satisfying the relevant precondition of ensuring it is shutdown.

 @param simulators the Simulators to Erase.
 @return A future wrapping the Simulators that this were erased.
 */
- (FBFuture<NSArray<FBSimulator *> *> *)eraseSimulators:(NSArray<FBSimulator *> *)simulators;

@end

NS_ASSUME_NONNULL_END

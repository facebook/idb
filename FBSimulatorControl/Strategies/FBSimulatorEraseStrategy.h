/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

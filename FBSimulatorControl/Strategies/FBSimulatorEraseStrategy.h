/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulator;
@class FBSimulatorSet;

NS_ASSUME_NONNULL_BEGIN

/**
 A Strategy for Erasing Simulator Contents.
 */
@interface FBSimulatorEraseStrategy : NSObject

/**
 Creates a FBSimulatorEraseStrategy.

 @param set the Simulator Set to create the strategy for,
 @return a configured FBSimulatorTerminationStrategy instance.
 */
+ (instancetype)strategyForSet:(FBSimulatorSet *)set;

/**
 Erases the provided Simulators, satisfying the relevant precondition of ensuring it is shutdown.

 @param simulators the Simulators to Erase.
 @param error an error out if any error occured.
 @return an array of the Simulators that this were erased if successful, nil otherwise.
 */
- (nullable NSArray<FBSimulator *> *)eraseSimulators:(NSArray<FBSimulator *> *)simulators error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

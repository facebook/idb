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
 A Strategy for Deleting Simulators.
 */
@interface FBSimulatorDeletionStrategy : NSObject

#pragma mark Initializers

/**
 Creates a FBSimulatorEraseStrategy.

 @param set the Simulator Set to log.
 @return a configured FBSimulatorTerminationStrategy instance.
 */
+ (instancetype)strategyForSet:(FBSimulatorSet *)set;

#pragma mark Public Methods

/**
 Intelligently Deletes Simulators.

 @param simulators the Simulators to Delete.
 @return a future wrapping the array of deleted simulator uuids.
 */
- (FBFuture<NSArray<NSString *> *> *)deleteSimulators:(NSArray<FBSimulator *> *)simulators;

@end

NS_ASSUME_NONNULL_END

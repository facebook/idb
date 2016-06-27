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
@protocol FBControlCoreLogger;

NS_ASSUME_NONNULL_BEGIN

/**
 A Strategy for Deleting Simulators.
 */
@interface FBSimulatorDeletionStrategy : NSObject

/**
 Creates a FBSimulatorEraseStrategy.

 @param set the Simulator Set to log.
 @return a configured FBSimulatorTerminationStrategy instance.
 */
+ (instancetype)strategyForSet:(FBSimulatorSet *)set;

/**
 Intelligently Deletes Simulators.

 @param simulators the Simulators to Delete.
 @param error an error out for any error that occurs.
 @return an Array of the UDIDs of all the deleted Simulators on success, nil otherwise.
 */
- (nullable NSArray<NSString *> *)deleteSimulators:(NSArray<FBSimulator *> *)simulators error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

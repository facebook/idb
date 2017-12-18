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

@class FBProcessInfo;
@class FBSimulator;

/**
 A Strategy for Terminating the Suprocesses of a Simulator, whether they be Applications or regular spawned processes.
 */
@interface FBSimulatorSubprocessTerminationStrategy : NSObject

#pragma mark Initializers

/**
 Creates and Returns a Strategy for Terminating the Subprocesses of a Simulator's 'launchd_sim'

 @param simulator the Simulator to Terminate Processes.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator;

#pragma mark Public Methods

/**
 Terminates a Process for a Simulator.
 Will fail if the Process does not belong to the Simulator.
 Uses the highest-level API available for doing-so.

 @param process the Process to terminate.
 @return A future that resolves successfully if the process is terminated.
 */
- (FBFuture<NSNull *> *)terminate:(FBProcessInfo *)process;

@end

NS_ASSUME_NONNULL_END

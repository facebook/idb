/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAgentLaunchConfiguration;
@class FBSimulator;
@class FBSimulatorAgentOperation;

/**
 A Strategy for Launching Agents on a Simulator.
 */
@interface FBAgentLaunchStrategy : NSObject

#pragma mark Initializer

/**
 Creates a Strategy for the provided Simulator.

 @param simulator the Simulator to launch on.
 @return a new Agent Launch Strategy.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator;

#pragma mark Long-Running Processes

/**
 Launches a long-running process with the given configuration.

 @param agentLaunch the agent to launch.
 @return an Agent Launch Operation, wrapped in a future.
 */
- (FBFuture<FBSimulatorAgentOperation *> *)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch;

#pragma mark Short-Running Processes

/**
 Launches a short-running process with the given configuration.

 @param agentLaunch the agent to launch.
 @return the stat_loc exit of the process, wrapped in a Future.
 */
- (FBFuture<NSNumber *> *)launchAndNotifyOfCompletion:(FBAgentLaunchConfiguration *)agentLaunch;

/**
 Launches an agent, consuming it's output and returning it as a String.

 @param agentLaunch the configuration for launching the process. The 'output' of the configuration will be ignored.
 @return A future that wraps the stdout of the launched process.
 */
- (FBFuture<NSString *> *)launchConsumingStdout:(FBAgentLaunchConfiguration *)agentLaunch;

@end

NS_ASSUME_NONNULL_END

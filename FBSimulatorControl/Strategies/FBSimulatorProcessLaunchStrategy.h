/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcessSpawnConfiguration;
@class FBSimulator;

@protocol FBLaunchedProcess;

/**
 A Strategy for launching processes on a Simulator.
 */
@interface FBSimulatorProcessLaunchStrategy : NSObject

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
 @return a future, wrapping the launched process.
 */
- (FBFuture<id<FBLaunchedProcess>> *)launchAgent:(FBProcessSpawnConfiguration *)agentLaunch;

#pragma mark Short-Running Processes

/**
 Launches a short-running process with the given configuration.

 @param agentLaunch the agent to launch.
 @return the stat_loc exit of the process, wrapped in a Future.
 */
- (FBFuture<NSNumber *> *)launchAndNotifyOfCompletion:(FBProcessSpawnConfiguration *)agentLaunch;

/**
 Launches an agent, consuming it's output and returning it as a String.

 @param agentLaunch the configuration for launching the process. The 'output' of the configuration will be ignored.
 @return A future that wraps the stdout of the launched process.
 */
- (FBFuture<NSString *> *)launchConsumingStdout:(FBProcessSpawnConfiguration *)agentLaunch;

#pragma mark Helpers

/**
 Builds the CoreSimulator launch Options for Launching an App or Process on a Simulator.

 @param arguments the arguments to use.
 @param environment the environment to use.
 @param waitForDebugger YES if the Application should be launched waiting for a debugger to attach. NO otherwise.
 @return a Dictionary of the Launch Options.
 */
+ (NSDictionary<NSString *, id> *)launchOptionsWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger;

@end

NS_ASSUME_NONNULL_END

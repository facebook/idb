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
 @return a new process launch strategy.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator;

#pragma mark Long-Running Processes

/**
 Launches a long-running process with the given configuration.

 @param configuration the configuration of the process to spawn.
 @return a future, wrapping the launched process.
 */
- (FBFuture<id<FBLaunchedProcess>> *)launchProcess:(FBProcessSpawnConfiguration *)configuration;

#pragma mark Short-Running Processes

/**
 Launches a short-running process with the given configuration.

 @param configuration the configuration of the process to spawn.
 @return the stat_loc exit of the process, wrapped in a Future.
 */
- (FBFuture<NSNumber *> *)launchAndNotifyOfCompletion:(FBProcessSpawnConfiguration *)configuration;

/**
 Launches an process, consuming it's output and returning it as a String.

 @param configuration the configuration of the process to spawn.
 @return A future that wraps the stdout of the launched process.
 */
- (FBFuture<NSString *> *)launchConsumingStdout:(FBProcessSpawnConfiguration *)configuration;

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

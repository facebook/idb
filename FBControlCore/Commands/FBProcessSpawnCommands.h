/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcessSpawnConfiguration;

@protocol FBLaunchedProcess;

/**
 Commands relating to the launching of processes on a target.
 */
@protocol FBProcessSpawnCommands <NSObject, FBiOSTargetCommand>

/**
 Launches the provided process on the target with the provided configuration.

 @param configuration the configuration of the process to launch.
 @return A future wrapping the launched process.
 */
- (FBFuture<id<FBLaunchedProcess>> *)launchProcess:(FBProcessSpawnConfiguration *)configuration;

@end

/**
 More convenience.
 */
@interface FBProcessSpawnCommandHelpers : NSObject

#pragma mark Short-Running Processes

/**
 Launches a short-running process with the given configuration.

 @param configuration the configuration of the process to spawn.
 @param commands the command implementation to use.
 @return the stat_loc exit of the process, wrapped in a Future.
 */
+ (FBFuture<NSNumber *> *)launchAndNotifyOfCompletion:(FBProcessSpawnConfiguration *)configuration withCommands:(id<FBProcessSpawnCommands>)commands;

/**
 Launches an process, consuming it's output and returning it as a String.

 @param configuration the configuration of the process to spawn.
 @param commands the command implementation to use.
 @return A future that wraps the stdout of the launched process.
 */
+ (FBFuture<NSString *> *)launchConsumingStdout:(FBProcessSpawnConfiguration *)configuration withCommands:(id<FBProcessSpawnCommands>)commands;

@end

NS_ASSUME_NONNULL_END

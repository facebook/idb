/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcess;
@class FBProcessIOAttachment;
@class FBProcessSpawnConfiguration;

@protocol FBControlCoreLogger;

/**
 Commands relating to the launching of processes on a target.
 */
@protocol FBProcessSpawnCommands <NSObject, FBiOSTargetCommand>

/**
 Launches the provided process on the target with the provided configuration.

 @param configuration the configuration of the process to launch.
 @return A future wrapping the launched process.
 */
- (FBFuture<FBProcess *> *)launchProcess:(FBProcessSpawnConfiguration *)configuration;

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

/**
 Resolves an exitCode future from a statLoc.
 Performs the necessary unwapping of the statLoc bitmask.
 
 @param statLoc the stat_loc value.
 @param attachment the IO attachment of the process.
 @param statLocFuture the statLoc future to resolve.
 @param exitCodeFuture the exitCode future to resolve.
 @param signalFuture the signal future to resolve.
 @param processIdentifier the pid of the finished process.
 @param queue a queue to use for chaining
 @param configuration the configuration of the finished process.
 @param logger the logger to log to.
 */
+ (void)resolveProcessFinishedWithStatLoc:(int)statLoc inTeardownOfIOAttachment:(FBProcessIOAttachment *)attachment statLocFuture:(FBMutableFuture<NSNumber *> *)statLocFuture exitCodeFuture:(FBMutableFuture<NSNumber *> *)exitCodeFuture signalFuture:(FBMutableFuture<NSNumber *> *)signalFuture processIdentifier:(pid_t)processIdentifier configuration:(FBProcessSpawnConfiguration *)configuration queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END

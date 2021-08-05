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

@protocol FBControlCoreLogger;
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

/**
 Signal a launched process.
 The future returned will resolve when the process has terminated and can be ignored if not required.

 @param signo the signal number to send.
 @param process the process to signal
 @return a successful Future that resolves to the signal number when the process has terminated.
 */
+ (FBFuture<NSNumber *> *)sendSignal:(int)signo toProcess:(id<FBLaunchedProcess>)process;

/**
 A mechanism for sending an signal to a task, backing off to a kill.
 If the process does not die before the timeout is hit, a SIGKILL will be sent.

 @param signo the signal number to send.
 @param timeout the timeout to wait before sending a SIGKILL.
 @param process the process to kill.
 @param logger used for log information when timeout happened, may be nil.
 @return a future that resolves to the signal sent when the process has been terminated.
 */
+ (FBFuture<NSNumber *> *)sendSignal:(int)signo backingOffToKillWithTimeout:(NSTimeInterval)timeout toProcess:(id<FBLaunchedProcess>)process logger:(nullable id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END

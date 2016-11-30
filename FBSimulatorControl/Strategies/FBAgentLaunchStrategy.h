/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBAgentLaunchConfiguration;
@class FBProcessInfo;
@class FBSimulator;

NS_ASSUME_NONNULL_BEGIN

/**
 A Typedef for a Callback.
 */
typedef void (^FBAgentLaunchCallback)(void);

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
+ (instancetype)withSimulator:(FBSimulator *)simulator;

#pragma mark Public Methdds

/**
 Launches an agent with the given configuration.

 @param agentLaunch the agent to launch.
 @param error an error out for any error that occurs.
 @return the Process Info of the launched agent, nil if there was a failure.
 */
- (nullable FBProcessInfo *)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch error:(NSError **)error;

/**
 Spawns an long-lived executable on the Simulator.
 The Task should not terminate in less than a few seconds, as Process Info will be obtained.

 @param launchPath the path to the binary.
 @param options the Options to use in the launch.
 @param terminationHandler a Termination Handler for when the process dies.
 @param error an error out for any error that occured.
 @return the Process Identifier of the launched process, nil otherwise.
 */
- (nullable FBProcessInfo *)spawnLongRunningWithPath:(NSString *)launchPath options:(nullable NSDictionary<NSString *, id> *)options terminationHandler:(nullable FBAgentLaunchCallback)terminationHandler error:(NSError **)error;

/**
 Spawns an short-lived executable on the Simulator.
 The Process Identifier of the task will be returned, but will be invalid by the time it is returned if the process is short-lived.
 Will block for timeout seconds to confirm that the process terminates

 @param launchPath the path to the binary.
 @param options the Options to use in the launch.
 @param timeout the number of seconds to wait for the process to terminate.
 @param error an error out for any error that occured.
 @return the Process Identifier of the launched process, -1 otherwise.
 */
- (pid_t)spawnShortRunningWithPath:(NSString *)launchPath options:(nullable NSDictionary<NSString *, id> *)options timeout:(NSTimeInterval)timeout error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

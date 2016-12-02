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
 Launches an agent, consuming it's output.

 @param agentLaunch the configuration for launching the process. The 'output' of the configuration will be ignored.
 @param error an error out for any error that occurs.
 @return the stdout of the launched process, nil on error.
 */
- (nullable NSString *)launchConsumingStdout:(FBAgentLaunchConfiguration *)agentLaunch error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

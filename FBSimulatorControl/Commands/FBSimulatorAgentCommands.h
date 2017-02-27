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
@class FBBinaryDescriptor;
@class FBSimulator;

NS_ASSUME_NONNULL_BEGIN

/**
 Commands relating to the launching of Agents on a Simulator.
 */
@protocol FBSimulatorAgentCommands <NSObject>

/**
 Launches the provided Agent with the given Configuration.

 @param agentLaunch the Agent Launch Configuration to Launch.
 @param error an error out for any error that occurs.
 @return YES if the command succeeds, NO otherwise,
 */
- (BOOL)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch error:(NSError **)error;

/**
 Launches the provided Agent.

 @param agent the Agent Launch Configuration to Launch.
 @param error an error out for any error that occurs.
 @return YES if the command succeeds, NO otherwise,
 */
- (BOOL)killAgent:(FBBinaryDescriptor *)agent error:(NSError **)error;

@end

/**
 An Implementation of FBSimulatorAgentCommands.
 */
@interface FBSimulatorAgentCommands : NSObject <FBSimulatorAgentCommands>

/**
 The Designated Intializer

 @param simulator the Simulator.
 @return a new Simulator Agent Commands Instance.
 */
+ (instancetype)commandsWithSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END

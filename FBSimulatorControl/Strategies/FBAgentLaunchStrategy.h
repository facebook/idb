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
@protocol FBFileConsumer;

NS_ASSUME_NONNULL_BEGIN

/**
 The Defined Callback for an Agent.

 The parameter to the block is an integer from waitpid(2).
 This is a bitmasked integer, so information about the exit of the process
 can be obtained using the macros defined in <sys/wait.h>
 The details of these macros are documented in the manpage for waitpid.
 */
typedef void (^FBAgentLaunchHandler)(int stat_loc);

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

#pragma mark Public Methdds

/**
 Launches an agent with the given configuration.

 @param agentLaunch the agent to launch.
 @param error an error out for any error that occurs.
 @return the Process Info of the launched agent, nil if there was a failure.
 */
- (nullable FBProcessInfo *)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch error:(NSError **)error;

/**
 Launches an agent with the given configuration.

 @param agentLaunch the agent to launch.
 @param terminationHandler the Termnation Handler to call when the process has terminated.
 @param error an error out for any error that occurs.
 @return the Process Info of the launched agent, nil if there was a failure.
 */
- (nullable FBProcessInfo *)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch terminationHandler:(nullable FBAgentLaunchHandler)terminationHandler error:(NSError **)error;

/**
 Launches an agent with the provided parameters.

 @param launchPath to the executable to launch.
 @param arguments the arguments.
 @param environment the environment
 @param waitForDebugger YES if the process should be launched waiting for a debugger to attach. NO otherwise.
 @param stdOut the stdout to use, may be nil.
 @param stdErr the stderr to use, may be nil.
 @param error an error out for any error that occurs.
 @return the Process Info of the launched agent, nil if there was a failure.
 */
- (nullable FBProcessInfo *)launchAgentWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOut:(nullable NSFileHandle *)stdOut stdErr:(nullable NSFileHandle *)stdErr terminationHandler:(nullable FBAgentLaunchHandler)terminationHandler error:(NSError **)error;

/**
 Launches an agent, consuming it's output with the consumer.

 @param agentLaunch the configuration for launching the process. The 'output' of the configuration will be ignored.
 @param consumer the consumer to consume with.
 @param error an error out for any error that occurs.
 @return the stdout of the launched process, nil on error.
 */
- (BOOL)launchAndWait:(FBAgentLaunchConfiguration *)agentLaunch consumer:(id<FBFileConsumer>)consumer error:(NSError **)error;

/**
 Launches an agent, consuming it's output and returning it as a String.

 @param agentLaunch the configuration for launching the process. The 'output' of the configuration will be ignored.
 @param error an error out for any error that occurs.
 @return the stdout of the launched process, nil on error.
 */
- (nullable NSString *)launchConsumingStdout:(FBAgentLaunchConfiguration *)agentLaunch error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

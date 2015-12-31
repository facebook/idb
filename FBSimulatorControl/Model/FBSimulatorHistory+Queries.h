/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBProcessInfo.h>
#import <FBSimulatorControl/FBSimulatorHistory.h>

@class FBAgentLaunchConfiguration;
@class FBApplicationLaunchConfiguration;

/**
 Queries for obtaining information from Session State
 */
@interface FBSimulatorHistory (Queries)

/**
 Returns Process Info for currently-running applications.
 Does not reach into previous states.

 @return an NSArray<FBProcessInfo> of the currently running, User Launched Applications.
 */
- (NSArray *)launchedApplicationProcesses;

/**
 Returns Process Info for currently-running agents.
 Does not reach into history.

 @return an NSArray<FBProcessInfo> of the currently running, User Launched Agents.
 */
- (NSArray *)launchedAgentProcesses;

/**
 Returns all of the Agents and Applications that have been launched, in the order that they were launched.
 Reaches into history in order to find Agents and Applications that have terminated.

 @return An NSArray<FBProcessInfo> of All Launched Processes, most recent first.
 */
- (NSArray *)allUserLaunchedProcesses;

/**
 Returns all of the Applications that have been launched, in the order that they were launched.
 Reaches into history in order to find Applications that have terminated.

 @return An NSArray<FBProcessInfo> of All Launched Application Processes, most recent first.
 */
- (NSArray *)allLaunchedApplicationProcesses;

/**
 Returns all of the Agents that have been launched, in the order that they were launched.
 Reaches into previous states in order to find Agents that have terminated.

 @return An NSArray<FBProcessInfo> of All Launched Agent Processes, most recent first.
 */
- (NSArray *)allLaunchedAgentProcesses;

/**
 Returns all Process Launch Configurations.
 Reaches into previous states in order to find Processes that have terminated.

 @return An NSArray<FBProcessLaunchConfiguration> of all historical Process Launches. Ordering is arbitrary.
 */
- (NSArray *)allProcessLaunches;
 @return An NSArray<FBApplicationLaunchConfiguration> of all historical Application Launches. Ordering is arbitrary.
 */
- (NSArray *)allProcessLaunches;

/**
 Returns Process Info for the Application that was launched most recently.
 Reaches into previous states in order to find Applications that have been terminated.

 @return An FBProcessInfo for the most recently launched Application, nil if no Application has been launched.
 */
- (FBProcessInfo *)lastLaunchedApplicationProcess;

/**
 Returns Process Info for the Agent that was launched most recently.
 Reaches into previous states in order to find Agents that have been terminated.

 @return An FBProcessInfo for the most recently launched Agent, nil if no Agent has been launched.
 */
- (FBProcessInfo *)lastLaunchedAgentProcess;

/**
 Returns the Launch Configration for the Application that was launched most recently.
 Reaches into previous states in order to find Applications that have been terminated.

 @return A FBApplicationLaunchConfiguration for the most recently launched Application, nil if no Application has been launched.
 */
- (FBApplicationLaunchConfiguration *)lastLaunchedApplication;

/**
 Returns the Launch Configration for the Agent that was launched most recently.
 Reaches into previous states in order to find Applications that have been terminated.

 @return An A FBAgentLaunchConfiguration for the most recently launched Agent, nil if no Agent has been launched.
 */
- (FBAgentLaunchConfiguration *)lastLaunchedAgent;

/**
 Returns the Process State for the given launch configuration, does not reach into previous states.

 @param launchConfig the Launch Configuration to filter running processes by.
 @return a FBUserLaunchedProcess for a running process that matches the launch configuration, nil otherwise.
 */
- (FBProcessInfo *)runningProcessForLaunchConfiguration:(FBProcessLaunchConfiguration *)launchConfig;

/**
 Returns the Process State for the given binary, does not reach into previous states.

 @param binary the Binary of the Launched process to filter running processes by.
 @return a FBUserLaunchedProcess for a running process that matches the launch configuration, nil otherwise.
 */
- (FBProcessInfo *)runningProcessForBinary:(FBSimulatorBinary *)binary;

/**
 Returns the Process State for the given Application, does not reach into previous states.

 @param application the Application of the Launched process to filter running processes by.
 @return a FBUserLaunchedProcess for a running process that matches the launch configuration, nil otherwise.
 */
- (FBProcessInfo *)runningProcessForApplication:(FBSimulatorApplication *)application;

/**
 Finds the first diagnostic for the provided name, matching the application.
 Reaches into previous states in order to find Diagnostics for Applications that have been terminated.

 @param name the Name of the Diagnostic to search for.
 @param application the Application's diagnostic to search for.
 @return the diagnostic data associated with the query, nil if none could be found.
 */
- (id<NSCopying, NSCoding>)diagnosticNamed:(NSString *)name forApplication:(FBSimulatorApplication *)application;

/**
 Returns the History representing the last change to Simulator State.

 @param state the state change to search for.
 @return the history of the prior change to the given state, or nil if this change never occurred.
 */
- (instancetype)lastChangeOfState:(FBSimulatorState)state;

/**
 An NSArray<FBSimulatorHistory> of the changes to the `simulatorState` property.
 */
- (NSArray *)changesToSimulatorState;

/**
 The timestamp of the first state.
 */
- (NSDate *)startDate;

@end

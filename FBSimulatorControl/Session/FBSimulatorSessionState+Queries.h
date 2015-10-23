/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSImulatorControl/FBSimulatorProcess.h>

#import <FBSimulatorControl/FBSimulatorSessionState.h>

@class FBAgentLaunchConfiguration;
@class FBApplicationLaunchConfiguration;

/**
 Queries for obtaining information from Session State
 */
@interface FBSimulatorSessionState (Queries)

/**
 Returns all of the Agents and Applications that have been launched, in the order that they were launched.
 Reaches into previous states in order to find Agents and Applications that have been terminated.

 @return An NSArray<NSUserLaunchedProcess> of All Launched Processes, most recent first.
 */
- (NSArray *)allUserLaunchedProcesses;

/**
 Returns all of the Applications that have been launched, in the order that they were launched.
 Reaches into previous states in order to find Applications that have been terminated.
 An NSArray<NSUserLaunchedProcess>

 @return An NSArray<NSUserLaunchedProcess> of All Launched Applications, most recent first.
 */
- (NSArray *)allLaunchedApplications;

/**
 Returns all of the Agents that have been launched, in the order that they were launched.
 Reaches into previous states in order to find Agents that have been terminated.

 @return An NSArray<NSUserLaunchedProcess> of All Launched Agents, most recent first.
 */
- (NSArray *)allLaunchedAgents;

/**
 Returns the Application that was launched most recently.
 Reaches into previous states in order to find Applications that have been terminated.

 @return An FBAgentLaunchConfiguration for the most recently launched Application, nil if no Application has been launched.
 */
- (FBApplicationLaunchConfiguration *)lastLaunchedApplication;

/**
 Returns the Agent that was launched most recently.
 Reaches into previous states in order to find Agents that have been terminated.

 @return An FBAgentLaunchConfiguration for the most recently launched Agent, nil if no Agent has been launched.
 */
- (FBAgentLaunchConfiguration *)lastLaunchedAgent;

/**
 Returns the Process State for the given launch configuration, does not reach into previous states.

 @param launchConfig the Launch Configuration to filter running processes by.
 @return a FBUserLaunchedProcess for a running process that matches the launch configuration, nil otherwise.
 */
- (FBUserLaunchedProcess *)runningProcessForLaunchConfiguration:(FBProcessLaunchConfiguration *)launchConfig;

/**
 Returns the Process State for the given binary, does not reach into previous states.

 @param binary the Binary of the Launched process to filter running processes by.
 @return a FBUserLaunchedProcess for a running process that matches the launch configuration, nil otherwise.
 */
- (FBUserLaunchedProcess *)runningProcessForBinary:(FBSimulatorBinary *)binary;

/**
 Returns the Process State for the given Application, does not reach into previous states.

 @param application the Application of the Launched process to filter running processes by.
 @return a FBUserLaunchedProcess for a running process that matches the launch configuration, nil otherwise.
 */
- (FBUserLaunchedProcess *)runningProcessForApplication:(FBSimulatorApplication *)application;

/**
 Returns Agent State for all running agents, does not reach into previous states.

 @return an NSArray<FBUserLaunchedProcess> of the currently running, User Launched Agents.
 */
- (NSArray *)runningAgents;

/**
 Returns Application State for all running applications, does not reach into previous states.

 @return an NSArray<FBUserLaunchedProcess> of the currently running, User Launched Applications.
 */
- (NSArray *)runningApplications;

/**
 Finds the first diagnostic for the provided name, matching the application.
 Reaches into previous states in order to find Diagnostics for Applications that have been terminated.

 @param the Name of the Diagnostic to search for.
 @param application the Application's diagnostic to search for.
 @return the diagnostic data associated with the query, nil if none could be found.
 */
- (id)diagnosticNamed:(NSString *)name forApplication:(FBSimulatorApplication *)application;

/**
 Reaches into previous states in order to find Diagnostics for Applications.
 */
- (NSDictionary *)allProcessDiagnostics;

/**
 Describes the `simulatorState` changes.
 */
- (NSArray *)changesToSimulatorState;

/**
 The date of the first session state.
 */
- (NSDate *)sessionStartDate;

@end

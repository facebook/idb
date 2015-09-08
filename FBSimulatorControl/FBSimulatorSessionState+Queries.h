/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSessionState.h"

@class FBAgentLaunchConfiguration;
@class FBApplicationLaunchConfiguration;

/**
 Queries for obtaining information from Session State
 */
@interface FBSimulatorSessionState (Queries)

/**
 Returns the Application that was launched most recently.
 Reaches into previous states in order to find Applications that have been terminated.
 */
- (FBApplicationLaunchConfiguration *)lastLaunchedApplication;

/**
 Returns the Agent that was launched most recently.
 Reaches into previous states in order to find Agents that have been terminated.
 */
- (FBAgentLaunchConfiguration *)lastLaunchedAgent;

/**
 Returns the Process State for the given launch configuration, does not reach into previous states.
 */
- (FBSimulatorSessionProcessState *)processForLaunchConfiguration:(FBProcessLaunchConfiguration *)launchConfig;

/**
 Returns the Process State for the given binary, does not reach into previous states.
 */
- (FBSimulatorSessionProcessState *)processForBinary:(FBSimulatorBinary *)binary;

/**
 Returns the Process State for the given Application, does not reach into previous states.
 */
- (FBSimulatorSessionProcessState *)processForApplication:(FBSimulatorApplication *)application;

/**
 Returns Agent State for all running agents, does not reach into previous states.
 */
- (NSArray *)runningAgents;

/**
 Returns Application State for all running applications, does not reach into previous states.
 */
- (NSArray *)runningApplications;

/**
 Finds the first diagnostic for the provided name, matching the application.
 Reaches into previous states in order to find Diagnostics for Applications that have been terminated.
 */
- (id)diagnosticNamed:(NSString *)name forApplication:(FBSimulatorApplication *)application;

/**
 Reaches into previous states in order to find Diagnostics for Applications.
 */
- (NSDictionary *)allDiagnostics;

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorSession.h>
#import <FBSimulatorControl/FBSimulatorSessionInteraction.h>

@class FBAgentLaunchConfiguration;
@class FBApplicationLaunchConfiguration;

/**
 Conveniences for starting managing the Session Lifecycle.
 */
@interface FBSimulatorSession (Convenience)

/**
 Starts the Simulator Session with the configuration object.
 1) Launches the Simulator
 2) Installs the Application
 3) Launches the Application
 4) Launches the Agent

 @param error an Error Out for any error that occured.
 @returns YES if the interaction was successful, NO otherwise.
 */
- (BOOL)startWithAppLaunch:(FBApplicationLaunchConfiguration *)appLaunch agentLaunch:(FBAgentLaunchConfiguration *)agentLaunch error:(NSError **)error;

/**
 Re-launches the last terminated application.
 */
- (BOOL)relaunchAppWithError:(NSError **)error;

/**
 Terminates the last launched application.
 */
- (BOOL)terminateAppWithError:(NSError **)error;

@end

@interface FBSimulatorSessionInteraction (Convenience)

- (instancetype)startWithAppLaunch:(FBApplicationLaunchConfiguration *)appLaunch agentLaunch:(FBAgentLaunchConfiguration *)agentLaunch;

@end

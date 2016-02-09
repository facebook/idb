/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorInteraction.h>

@class FBApplicationLaunchConfiguration;

@interface FBSimulatorInteraction (Applications)

/**
 Installs the given Application.
 Will Allways Succeed if the Application is a System Application.

 @param application the Application to Install.
 @return the reciever, for chaining.
 */
- (instancetype)installApplication:(FBSimulatorApplication *)application;

/**
 Launches the Application with the given Configuration.
 If the Application is determined to allready be running, the interaction will fail.

 @param appLaunch the Application Launch Configuration to Launch.
 @return the reciever, for chaining.
 */
- (instancetype)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch;

/**
 Launches the Application with the given Configuration, or Re-Launches it.
 A Relaunch is a kill of the currently launched application, followed by a launch.

 @param appLaunch the Application Launch Configuration to Launch.
 @return the reciever, for chaining.
 */
- (instancetype)launchOrRelaunchApplication:(FBApplicationLaunchConfiguration *)appLaunch;

/**
 Relaunches the last-launched Application:
 - If the Application is running, it will be killed first then launched.
 - If the Application has terminated, it will be launched.
 - If no Application has been launched yet, the interaction will fail.

 @return the reciever, for chaining.
 */
- (instancetype)relaunchLastLaunchedApplication;

/**
 Terminates the last-launched Application:
 - If the Application is running, it will be killed first then launched.
 - If the Application has terminated, the interaction will fail.
 - If no Application has been launched yet, the interaction will fail.

 @return the reciever, for chaining.
 */
- (instancetype)terminateLastLaunchedApplication;

@end

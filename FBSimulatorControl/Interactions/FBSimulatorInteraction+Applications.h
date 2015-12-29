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

 @param application the Application to Install.
 @return the reciever, for chaining.
 */
- (instancetype)installApplication:(FBSimulatorApplication *)application;

/**
 Launches the Application with the given Configuration.

 @param appLaunch the Application Launch Configuration to Launch.
 @return the reciever, for chaining.
 */
- (instancetype)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch;

/**
 Unix Signals the Application.

 @param signal the unix signo to send.
 @return the reciever, for chaining.
 */
- (instancetype)signal:(int)signal application:(FBSimulatorApplication *)application;

/**
 Kills the provided Application.

 @param application the Application to kill.
 @return the reciever, for chaining.
 */
- (instancetype)killApplication:(FBSimulatorApplication *)application;

@end

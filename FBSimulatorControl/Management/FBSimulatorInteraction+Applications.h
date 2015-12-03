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
 */
- (instancetype)installApplication:(FBSimulatorApplication *)application;

/**
 Launches the Application with the given Configuration.
 */
- (instancetype)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch;

/**
 Unix Signals the Application.
 */
- (instancetype)signal:(int)signal application:(FBSimulatorApplication *)application;

/**
 Kills the provided Application.
 */
- (instancetype)killApplication:(FBSimulatorApplication *)application;

@end

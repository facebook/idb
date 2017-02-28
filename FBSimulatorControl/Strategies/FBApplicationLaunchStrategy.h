/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBApplicationDescriptor ;
@class FBApplicationLaunchConfiguration;
@class FBProcessInfo;
@class FBSimulator;

NS_ASSUME_NONNULL_BEGIN

/**
 A Strategy for Launching Applications.
 */
@interface FBApplicationLaunchStrategy : NSObject

/**
 Creates and returns a new Application Launch Strategy.

 @param simulator the Simulator to launch the Application on.
 @param useBridge YES if the SimulatorBridge should be used, NO otherwise.
 @return a new Application Launch Strategy.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator useBridge:(BOOL)useBridge;

/**
 Creates and returns a new Application Launch Strategy.
 Uses the default of CoreSimulator to launch the Application

 @param simulator the Simulator to launch the Application on.
 @return a new Application Launch Strategy.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator;

/**
 Launches and returns the process info for the launched application.

 @param appLaunch the Application Configuration to Launch.
 @param error an error out for any error that occurs.
 @return a Process Info if the Application was launched, nil otherwise.
 */
- (nullable FBProcessInfo *)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch error:(NSError **)error;

/**
 Uninstalls an Application.

 @param bundleID the bundleID of the Application to uninstall.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)uninstallApplication:(NSString *)bundleID error:(NSError **)error;

/**
 Launches the Application with the given Configuration, or Re-Launches it.
 A Relaunch is a kill of the currently launched application, followed by a launch.

 @param appLaunch the Application to Re-Launch.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)launchOrRelaunchApplication:(FBApplicationLaunchConfiguration *)appLaunch error:(NSError **)error;

/**
 Relaunches the last-known-launched Application:
 - If the Application is running, it will be killed first then launched.
 - If the Application has terminated, it will be launched.
 - If no known Application has been launched yet, the interaction will fail.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)relaunchLastLaunchedApplicationWithError:(NSError **)error;

/**
 Terminates the last-launched Application:
 - If the Application is running, it will be killed first then launched.
 - If the Application has terminated, the call will fail.
 - If no known Application has been launched yet, the call will fail.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)terminateLastLaunchedApplicationWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

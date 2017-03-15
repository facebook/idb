/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;

/**
 Simulator-Specific Application Commands.
 */
@protocol FBSimulatorApplicationCommands <FBApplicationCommands>

#pragma mark Installing Applications

/**
 Installs the given Application.
 Will always succeed if the Application is a System Application.

 @param application the Application to Install.
 @param error an error out for any error that occurs.
 @return YES if the command succeeds, NO otherwise,
 */
- (BOOL)installApplication:(FBApplicationDescriptor *)application error:(NSError **)error;

#pragma mark Launching / Terminating Applications

/**
 Uninstalls the given Application.
 Will always fail if the Application is a System Application.

 @param bundleID the Bundle ID of the application to uninstall.
 @param error an error out for any error that occurs.
 @return YES if the command succeeds, NO otherwise,
 */
- (BOOL)uninstallApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error;

/**
 Launches the Application with the given Configuration, or Re-Launches it.
 A Relaunch is a kill of the currently launched application, followed by a launch.

 @param appLaunch the Application Launch Configuration to Launch.
 @param error an error out for any error that occurs.
 @return YES if the command succeeds, NO otherwise,
 */
- (BOOL)launchOrRelaunchApplication:(FBApplicationLaunchConfiguration *)appLaunch error:(NSError **)error;

/**
 Terminates an Application based on the Application.
 Will fail if a running Application could not be found, or the kill fails.

 @param application the Application to terminate.
 @param error an error out for any error that occurs.
 @return YES if the command succeeds, NO otherwise,
 */
- (BOOL)terminateApplication:(FBApplicationDescriptor *)application error:(NSError **)error;

/**
 Relaunches the last-known-launched Application:
 - If the Application is running, it will be killed first then launched.
 - If the Application has terminated, it will be launched.
 - If no known Application has been launched yet, the interaction will fail.

 @param error an error out for any error that occurs.
 @return YES if the command succeeds, NO otherwise,
 */
- (BOOL)relaunchLastLaunchedApplicationWithError:(NSError **)error;

/**
 Terminates the last-launched Application:
 - If the Application is running, it will be killed first then launched.
 - If the Application has terminated, the interaction will fail.
 - If no known Application has been launched yet, the interaction will fail.

 @param error an error out for any error that occurs.
 @return YES if the command succeeds, NO otherwise,
 */
- (BOOL)terminateLastLaunchedApplicationWithError:(NSError **)error;

#pragma mark Querying Application State

/**
 Fetches the FBApplicationDescriptor instance by Bundle ID, on the Simulator.

 @param bundleID the Bundle ID to fetch an installed application for.
 @param error an error out for any error that occurs.
 @return a FBApplicationDescriptor instance if one could be obtained, nil otherwise.
 */
- (nullable FBApplicationDescriptor *)installedApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error;

/**
 Determines whether a provided Bundle ID represents a System Application

 @param bundleID the Bundle ID to fetch an installed application for.
 @param error an error out for any error that occurs.
 @return YES if the Application with the provided is a System Application, NO otherwise.
 */
- (BOOL)isSystemApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error;

/**
 Determines the location of the Home Directory of an Application, it's chroot jail.

 @param bundleID the Bundle ID of the Application to search for,.
 @param error an error out for any error that occurs.
 @return the Home Directory of the Application if one was found, nil otherwise.
 */
- (nullable NSString *)homeDirectoryOfApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error;

/**
 Returns the Process Info for a Application by Bundle ID.

 @param bundleID the Bundle ID to fetch an installed application for.
 @param error an error out for any error that occurs.
 @return An FBProcessInfo for the Application if one is running, nil otherwise.
 */
- (nullable FBProcessInfo *)runningApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error;

@end

/**
 Implementation of FBApplicationCommands for Simulators.
 */
@interface FBSimulatorApplicationCommands : NSObject <FBSimulatorApplicationCommands>

/**
 Creates a FBSimulatorApplicationCommands instance.

 @param simulator the Simulator to perform actions on.
 @return a new FBSimulatorApplicationCommands instance.
 */
+ (instancetype)commandsWithSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END

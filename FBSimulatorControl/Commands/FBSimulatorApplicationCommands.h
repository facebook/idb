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
@class FBSimulatorApplicationOperation;

/**
 Simulator-Specific Application Commands.
 */
@protocol FBSimulatorApplicationCommands <FBApplicationCommands, FBiOSTargetCommand>

#pragma mark Application Lifecycle

/**
 Launches the Application with the given Configuration, or Re-Launches it.
 A Relaunch is a kill of the currently launched application, followed by a launch.

 @param appLaunch the Application Launch Configuration to Launch.
 @return A Future that resolves when the application is relaunched.
 */
- (FBFuture<NSNull *> *)launchOrRelaunchApplication:(FBApplicationLaunchConfiguration *)appLaunch;

#pragma mark Querying Application State

/**
 Fetches the FBApplicationBundle instance by Bundle ID, on the Simulator.

 @param bundleID the Bundle ID to fetch an installed application for.
 @param error an error out for any error that occurs.
 @return a FBApplicationBundle instance if one could be obtained, nil otherwise.
 */
- (nullable FBInstalledApplication *)installedApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error;

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
 @return A future that resolves with the process info of the running application.
 */
- (FBFuture<FBProcessInfo *> *)runningApplicationWithBundleID:(NSString *)bundleID;

@end

/**
 Implementation of FBApplicationCommands for Simulators.
 */
@interface FBSimulatorApplicationCommands : NSObject <FBSimulatorApplicationCommands>

@end

NS_ASSUME_NONNULL_END

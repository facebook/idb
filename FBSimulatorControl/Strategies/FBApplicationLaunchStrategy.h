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

@class FBApplicationBundle;
@class FBApplicationLaunchConfiguration;
@class FBProcessInfo;
@class FBSimulator;
@class FBSimulatorApplicationOperation;

/**
 A Strategy for Launching Applications.
 */
@interface FBApplicationLaunchStrategy : NSObject

#pragma mark Initializers

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

#pragma mark Public Methods

/**
 Launches and returns the process info for the launched application.

 @param appLaunch the Application Configuration to Launch.
 @return A Future that resolves with the launched Application.
 */
- (FBFuture<FBSimulatorApplicationOperation *> *)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch;

/**
 Launches the Application with the given Configuration, or Re-Launches it.
 A Relaunch is a kill of the currently launched application, followed by a launch.

 @param appLaunch the Application to Re-Launch.
 @return A Future that resolves with the launched Application.
 */
- (FBFuture<FBSimulatorApplicationOperation *> *)launchOrRelaunchApplication:(FBApplicationLaunchConfiguration *)appLaunch;

/**
 Uninstalls an Application.

 @param bundleID the bundleID of the Application to uninstall.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)uninstallApplication:(NSString *)bundleID error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

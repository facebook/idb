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

@end

NS_ASSUME_NONNULL_END

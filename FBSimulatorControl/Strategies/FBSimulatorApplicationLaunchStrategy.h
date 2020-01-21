/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBApplicationLaunchConfiguration;
@class FBBundleDescriptor;
@class FBProcessInfo;
@class FBSimulator;
@class FBSimulatorApplicationOperation;

/**
 A Strategy for Launching Applications inside a Simulator.
 */
@interface FBSimulatorApplicationLaunchStrategy : NSObject

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

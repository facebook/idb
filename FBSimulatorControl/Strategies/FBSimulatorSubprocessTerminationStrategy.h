/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcessInfo;
@class FBSimulator;

/**
 A Strategy for Terminating the Applications launched by a Simulator.
 */
@interface FBSimulatorSubprocessTerminationStrategy : NSObject

#pragma mark Initializers

/**
 Creates and Returns a Strategy for Terminating the Subprocesses of a Simulator's 'launchd_sim'

 @param simulator the Simulator to Terminate Processes.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator;

#pragma mark Public Methods

/**
 Terminates an Application Directly.

 @param bundleID the Bundle ID the bundle ID of the Application to terminate.
 @return a future that resolves successfully when the application is terminated.
 */
- (FBFuture<NSNull *> *)terminateApplication:(NSString *)bundleID;

@end

NS_ASSUME_NONNULL_END

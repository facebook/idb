/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBApplicationLaunchConfiguration;
@class FBSimulator;

/**
 An Operation for an Application.
 */
@interface FBSimulatorLaunchedApplication : NSObject <FBLaunchedApplication>

#pragma mark Helper Methods

/**
 Uses DISPATCH_PROC_EXIT to determine that the process has been terminated.

 @param simulator the Simulator that launched the process.
 @param processIdentifier the process identifier to monitor.
 @return a Future that resolves when the process has exited. Exit status is unknown.
 */
+ (FBFuture<NSNull *> *)terminationFutureForSimulator:(FBSimulator *)simulator processIdentifier:(pid_t)processIdentifier;

#pragma mark Properties

/**
 The Configuration Launched with.
 */
@property (nonatomic, copy, readonly) FBApplicationLaunchConfiguration *configuration;

@end

/**
 Private methods that should not be called by consumers.
 */
@interface FBSimulatorLaunchedApplication (Private)

/**
 The Designated Initializer.

 @param simulator the Simulator that launched the Application.
 @param configuration the configuration with which the application was launched.
 @param attachment the files to attach.
 @param launchFuture a future that resolves when the Application has finished launching.
 @return a new Application Operation.
 */
+ (FBFuture<FBSimulatorLaunchedApplication *> *)applicationWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationLaunchConfiguration *)configuration attachment:(FBProcessFileAttachment *)attachment launchFuture:(FBFuture<NSNumber *> *)launchFuture;

@end

NS_ASSUME_NONNULL_END

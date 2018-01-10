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
@class FBProcessInfo;
@class FBApplicationLaunchConfiguration;

/**
 An Operation for an Application.
 */
@interface FBSimulatorApplicationOperation : NSObject <FBiOSTargetContinuation>

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

/**
 The Launched Process Info.
 */
@property (nonatomic, copy, readonly) FBProcessInfo *process;

@end

/**
 Private methods that should not be called by consumers.
 */
@interface FBSimulatorApplicationOperation (Private)

/**
 The Designated Initializer.

 @param simulator the Simulator that launched the Application.
 @param configuration the configuration with which the application was launched.
 @param launchFuture a future that resolves when the Application has finished launching.
 @return a new Application Operation.
 */
+ (FBFuture<FBSimulatorApplicationOperation *> *)operationWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationLaunchConfiguration *)configuration launchFuture:(FBFuture<NSNumber *> *)launchFuture;

@end

NS_ASSUME_NONNULL_END

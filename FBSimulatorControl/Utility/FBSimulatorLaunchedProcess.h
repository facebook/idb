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

/**
 An implementation of FBLaunchedProcess for processes within a Simulator.
 The lifecycle of the process is managed internally and this class should not be instantiated directly by consumers.
 */
@interface FBSimulatorLaunchedProcess : NSObject <FBLaunchedProcess>

@end

/**
 Private methods that should not be called by consumers.
 */
@interface FBSimulatorLaunchedProcess (Private)

/**
 The Designated Initializer.

 @param simulator the Simulator the Process is launched in.
 @param configuration the configuration the process was launched with.
 @param attachment the IO attachment.
 @param launchFuture a future that will fire when the process has launched. The value is the process identifier.
 @param processStatusFuture a future that will fire when the process has terminated. The value is that of waitpid(2).
 @return a Future that resolves when the process is launched.
 */
+ (FBFuture<FBSimulatorLaunchedProcess *> *)processWithSimulator:(FBSimulator *)simulator configuration:(FBProcessSpawnConfiguration *)configuration attachment:(FBProcessIOAttachment *)attachment launchFuture:(FBFuture<NSNumber *> *)launchFuture processStatusFuture:(FBFuture<NSNumber *> *)processStatusFuture;

@end

NS_ASSUME_NONNULL_END

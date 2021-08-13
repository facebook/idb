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

/**
 The Designated Initializer.

 @param processIdentifier the process identifier of the launched process
 @param statLoc a future that will fire when the process has terminated. The value is that of waitpid(2).
 @param exitCode a future that will fire when the process exits. See -[FBLaunchedProcess exitCode]
 @param signal a future that will fire when the process is signalled. See -[FBLaunchedProcess signal]
 @param configuration the configuration the process was launched with.
 @return a Future that resolves when the process is launched.
 */
- (instancetype)initWithProcessIdentifier:(pid_t)processIdentifier statLoc:(FBFuture<NSNumber *> *)statLoc exitCode:(FBFuture<NSNumber *> *)exitCode signal:(FBFuture<NSNumber *> *)signal configuration:(FBProcessSpawnConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END

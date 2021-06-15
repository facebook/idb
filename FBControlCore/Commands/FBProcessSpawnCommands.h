/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcessSpawnConfiguration;

@protocol FBLaunchedProcess;

/**
 Commands relating to the launching of processes on a target.
 */
@protocol FBProcessSpawnCommands <NSObject, FBiOSTargetCommand>

/**
 Launches the provided process on the target with the provided configuration.

 @param configuration the configuration of the process to launch.
 @return A future wrapping the launched process.
 */
- (FBFuture<id<FBLaunchedProcess>> *)launchProcess:(FBProcessSpawnConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END

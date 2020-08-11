/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBFileContainer.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Defines an interface for interacting with the Data Container of Applications.
 */
@protocol FBFileCommands <NSObject, FBiOSTargetCommand>

/**
 Returns file commands for the given bundle id sandbox.

 @param bundleID the bundle ID of the container application.
 @return a Future context resolves with an instance of the file commands
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForContainerApplication:(NSString *)bundleID;

/**
 Returns file for the root of the filesystem

 @return a Future context that resolves with an instance of the file commands
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForRootFilesystem;

@end

NS_ASSUME_NONNULL_END

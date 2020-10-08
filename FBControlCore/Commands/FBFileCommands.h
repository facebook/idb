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

@protocol FBProvisioningProfileCommands;

/**
 Defines an interface for interacting with the Data Container of Applications.
 */
@protocol FBFileCommands <NSObject, FBiOSTargetCommand>

/**
 Returns a file container for the given bundle id sandbox.

 @param bundleID the bundle ID of the container application.
 @return a Future context that resolves with an implementation of the file container.
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForContainerApplication:(NSString *)bundleID;

/**
 Returns a file container for the root of the filesystem

 @return a Future context that resolves with an implementation of the file container.
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForRootFilesystem;

/**
 Returns a file container for the 'media' directory.

 @return a Future context that resolves with an implementation of the file container.
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForMediaDirectory;

/**
 Returns a file container for Provisioning Profiles.

 @return a Future context that resolves with an implementation of the file container.
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForProvisioningProfiles;

/**
 Returns a file container for MDM Profiles.

 @return a Future context that resolves with an implementation of the file container.
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForMDMProfiles;

/**
 Returns a file container for modification of the Springboard icon layout.

 @return a Future context that resolves with an implementation of the file container.
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForSpringboardIconLayout;

/**
 Returns a file container for modification wallpaper.

 @return a Future context that resolves with an implementation of the file container.
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForWallpaper;

@end

NS_ASSUME_NONNULL_END

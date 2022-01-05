/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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
  Defines an interface for obtaining "File Containers" for a variety of uses.
  When a file container has been obtained, it can be manipulated using the FBFileContainer protocol.
 */
@protocol FBFileCommands <NSObject, FBiOSTargetCommand>

/**
 Returns a file container for the given bundle id sandbox.

 @param bundleID the bundle ID of the container application.
 @return a Future context that resolves with an implementation of the file container.
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForContainerApplication:(NSString *)bundleID;

/**
 Returns a file container for the target's auxillary directory.

 @return a Future context that resolves with an implementation of the file container.
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForAuxillary;

/**
 Returns a file container for all of the application containers.

 @return a Future context that resolves with an implementation of the file container.
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForApplicationContainers;

/**
 Returns a file container for all of the group containers.

 @return a Future context that resolves with an implementation of the file container.
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForGroupContainers;

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

/**
 Returns a file container for disk image modification

 @return a Future context that resolves with an implementation of the file container.
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForDiskImages;

/**
 Returns a file container for manipulating device symbols.

 @return a Future context that resolves with an implementation of the file container.
 */
- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForSymbols;

@end

NS_ASSUME_NONNULL_END

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

@class FBDeveloperDiskImage;

@protocol FBDeveloperDiskImageCommands <NSObject, FBiOSTargetCommand>

/**
 Mounts the developer disk image, that is most suitable for the target.

 @return a Future wrapping the mounted image.
 */
- (FBFuture<FBDeveloperDiskImage *> *)ensureDiskImageIsMounted;

/**
 Mounts the provided developer disk image.

 @param diskImage the image to mount
 @return a Future wrapping the mounted image.
 */
- (FBFuture<FBDeveloperDiskImage *> *)mountDeveloperDiskImage:(FBDeveloperDiskImage *)diskImage;

/**
 Returns the mounted disk image. Fails if no image is mounted.

 @return a Future wrapping the mounted image.
 */
- (FBFuture<FBDeveloperDiskImage *> *)mountedDeveloperDiskImage;

/**
 Unmounts a developer disk image. Fails if no image is mounted.

 @return a Future when the image is unmounted.
 */
- (FBFuture<NSNull *> *)unmountDeveloperDiskImage;

/**
 Returns all disk images.

 @return the array of disk images.
 */
- (NSArray<FBDeveloperDiskImage *> *)availableDeveloperDiskImages;

@end

NS_ASSUME_NONNULL_END

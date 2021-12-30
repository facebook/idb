/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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

#pragma mark Managing Disk Images

/**
 Obtains the disk images that have been mounted, by finding the local image that has been mounted.

 @return a Future wrapping list of disk images..
 */
- (FBFuture<NSArray<FBDeveloperDiskImage *> *> *)mountedDiskImages;

/**
 Mounts the provided disk image.

 @param diskImage the image to mount
 @return a Future wrapping the mounted image.
 */
- (FBFuture<FBDeveloperDiskImage *> *)mountDiskImage:(FBDeveloperDiskImage *)diskImage;

/**
 Unmounts the provided disk image.

 @param diskImage the image to unmount.
 @return a Future when the image is unmounted.
 */
- (FBFuture<NSNull *> *)unmountDiskImage:(FBDeveloperDiskImage *)diskImage;

/**
 Returns all of the found, mountable disk images for the target.

 @return the array of disk images.
 */
- (NSArray<FBDeveloperDiskImage *> *)mountableDiskImages;

#pragma mark Developer Disk Images

/**
 Mounts the developer disk image, that is most suitable for the target.

 @return a Future wrapping the mounted image.
 */
- (FBFuture<FBDeveloperDiskImage *> *)ensureDeveloperDiskImageIsMounted;

@end

NS_ASSUME_NONNULL_END

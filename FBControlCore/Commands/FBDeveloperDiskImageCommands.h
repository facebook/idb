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

@end

NS_ASSUME_NONNULL_END

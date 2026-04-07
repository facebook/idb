/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

/**
 Commands to perform on a Simulator, related to photos/videos on the device
 */
@protocol FBSimulatorMediaCommandsProtocol <NSObject, FBiOSTargetCommand>

/**
 Add media files to the simulator

 @param mediaFileURLs local paths to the media files to add
 @return A future that resolves when the media has been added.
 */
- (nonnull FBFuture<NSNull *> *)addMedia:(nonnull NSArray<NSURL *> *)mediaFileURLs;

@end

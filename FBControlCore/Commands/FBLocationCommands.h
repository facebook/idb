/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Commands for manipulating location.
 */
@protocol FBLocationCommands <NSObject, FBiOSTargetCommand>

/**
 Overrides the location.

 @param longitude the longitude.
 @param latitude the latitude.
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)overrideLocationWithLongitude:(double)longitude latitude:(double)latitude;

@end

NS_ASSUME_NONNULL_END

/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBBitmapStreamConfiguration;
@protocol FBBitmapStream;

/**
 Bitmap Streaming Commands.
 */
@protocol FBBitmapStreamingCommands <NSObject, FBiOSTargetCommand>

/**
 Creates a Bitmap Stream for the iOS Target.

 @param configuration the stream configuration.
 @return A future that resolves with the Video Recording session.
 */
- (FBFuture<id<FBBitmapStream>> *)createStreamWithConfiguration:(FBBitmapStreamConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END

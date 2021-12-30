/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBVideoStreamConfiguration;
@protocol FBVideoStream;

/**
 Bitmap Streaming Commands.
 */
@protocol FBVideoStreamCommands <NSObject, FBiOSTargetCommand>

/**
 Creates a Bitmap Stream for the iOS Target.

 @param configuration the stream configuration.
 @return A future that resolves with the Video Recording session.
 */
- (FBFuture<id<FBVideoStream>> *)createStreamWithConfiguration:(FBVideoStreamConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END

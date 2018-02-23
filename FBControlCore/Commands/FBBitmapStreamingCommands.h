/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

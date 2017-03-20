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

@protocol FBBitmapStream;

/**
 Bitmap Streaming Commands.
 */
@protocol FBBitmapStreamingCommands

/**
 Creates a Bitmap Stream for a Simulator.

 @param error an error out for any error that occurs.
 @return the Video Recording session on success, nil otherwise.
 */
- (nullable id<FBBitmapStream>)createStreamWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

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

@class FBFramebufferSurface;
@protocol FBControlCoreLogger;

/**
 A Video Encoder using SimDisplayVideoWriter.
 */
@interface FBVideoEncoderSimulatorKit : NSObject

/**
 Create a new Encoder with the provided parameters.

 @param surface the surface to connect to.
 @param videoPath the video path to write to.
 @param logger the optional logger to log to.
 @return a new Encoder Instance.
 */
+ (instancetype)encoderWithRenderable:(FBFramebufferSurface *)surface videoPath:(NSString *)videoPath logger:(nullable id<FBControlCoreLogger>)logger;

/**
 YES if this class is supported, NO otherwise.
 */
+ (BOOL)isSupported;

/**
 Starts Recording Video.

 @param group the dispatch_group to put asynchronous work into. When the group's blocks have completed the recording has processed. If nil, an anonymous group will be created.
 */
- (void)startRecording:(dispatch_group_t)group;

/**
 Stops Recording Video.

 @param group the dispatch_group to put asynchronous work into. When the group's blocks have completed the recording has processed. If nil, an anonymous group will be created.
 */
- (void)stopRecording:(dispatch_group_t)group;

@end

NS_ASSUME_NONNULL_END

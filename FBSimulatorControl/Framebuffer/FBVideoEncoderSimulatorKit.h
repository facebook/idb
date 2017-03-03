/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBFramebufferVideo.h>

NS_ASSUME_NONNULL_BEGIN

@class FBFramebufferRenderable;
@protocol FBControlCoreLogger;

/**
 A Video Encoder using SimDisplayVideoWriter.
 */
@interface FBVideoEncoderSimulatorKit : NSObject <FBFramebufferVideo>

/**
 Create a new Encoder with the provided parameters.

 @param renderable the renderable to connect to.
 @param videoPath the video path to write to.
 @param logger the optional logger to log to.
 @return a new Encoder Instance.
 */
+ (instancetype)encoderWithRenderable:(FBFramebufferRenderable *)renderable videoPath:(NSString *)videoPath logger:(nullable id<FBControlCoreLogger>)logger;

/**
 YES if this class is supported, NO otherwise.
 */
+ (BOOL)isSupported;

@end

NS_ASSUME_NONNULL_END

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControl/FBFramebufferFrameGenerator.h>

NS_ASSUME_NONNULL_BEGIN

@class FBVideoEncoderConfiguration;
@protocol FBControlCoreLogger;

/**
 An built-in implementation of a video encoder, using AVFoundation.
 All media activity is serialized on a queue, this queue is internal and should not be used by clients.
 */
@interface FBVideoEncoderBuiltIn : NSObject <FBFramebufferFrameSink>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param configuration the configuration to use for encoding.
 @param logger the logger object to log events to, may be nil.
 @return a new Video Encoder instance.
 */
+ (instancetype)encoderWithConfiguration:(FBVideoEncoderConfiguration *)configuration videoPath:(NSString *)videoPath logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Starts Recording Video.
 */
- (FBFuture<NSNull *> *)startRecording;

/**
 Stops Recording Video.
 */
- (FBFuture<NSNull *> *)stopRecording;

#pragma mark Properties

/**
 The Queue used for Serializing Media Actions.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t mediaQueue;

@end

NS_ASSUME_NONNULL_END

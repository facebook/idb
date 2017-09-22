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

NS_ASSUME_NONNULL_BEGIN

@class FBFramebufferFrameGenerator;
@class FBFramebufferSurface;
@class FBVideoEncoderConfiguration;
@protocol FBControlCoreLogger;
@protocol FBSimulatorEventSink;

/**
 Controls the Recording of a Simulator's Framebuffer to a Video.
 */
@interface FBSimulatorVideo : NSObject <FBVideoRecordingSession>

/**
 The Initializer for a Frame Generator.

 @param configuration the configuration to use for encoding.
 @param frameGenerator the Frame Generator to register with.
 @param logger the logger object to log events to, may be nil.
 @param eventSink an event sink to report video output to.
 @return a new FBSimulatorVideo instance.
 */
+ (instancetype)videoWithConfiguration:(FBVideoEncoderConfiguration *)configuration frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink;

/**
 The Designated Initializer.

 @param configuration the configuration to use for encoding.
 @param surface the Renderable to Record.
 @param logger the logger object to log events to, may be nil.
 @param eventSink an event sink to report video output to.
 @return a new FBSimulatorVideo instance.
 */
+ (instancetype)videoWithConfiguration:(FBVideoEncoderConfiguration *)configuration surface:(FBFramebufferSurface *)surface logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink;

#pragma mark Public Methods

/**
 Starts Recording Video.

 @param filePath the (optional) file path to record to. If nil is provided, a default path will be used.
 @return A Future that resolves when recording has started.
 */
- (FBFuture<NSNull *> *)startRecordingToFile:(nullable NSString *)filePath;

/**
 Stops Recording Video.

 @return A Future that resolves when recording has stopped.
 */
- (FBFuture<NSNull *> *)stopRecording;

/**
 YES if Surface Based Supporting is available, NO otherwise.
 */
+ (BOOL)surfaceSupported;

@end

NS_ASSUME_NONNULL_END

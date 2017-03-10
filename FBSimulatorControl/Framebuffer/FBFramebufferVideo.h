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

@class FBFramebufferFrameGenerator;
@class FBFramebufferSurface;
@class FBVideoEncoderConfiguration;
@protocol FBControlCoreLogger;
@protocol FBSimulatorEventSink;

/**
 A Framebuffer Component that encodes video and writes to a file.
 */
@protocol FBFramebufferVideo <NSObject>

/**
 Starts Recording Video.

 @param filePath the (optional) file path to record to. If nil is provided, a default path will be used.
 @param group the dispatch_group to put asynchronous work into. When the group's blocks have completed the recording has processed. If nil, an anonymous group will be created.
 */
- (void)startRecordingToFile:(nullable NSString *)filePath group:(dispatch_group_t)group;

/**
 Stops Recording Video.

 @param group the dispatch_group to put asynchronous work into. When the group's blocks have completed the recording has processed. If nil, an anonymous group will be created.
 */
- (void)stopRecording:(dispatch_group_t)group;

@end

/**
 Implementations of FBFramebufferVideo.
 */
@interface FBFramebufferVideo : NSObject <FBFramebufferVideo>

/**
 The Initializer for a Frame Generator.

 @param configuration the configuration to use for encoding.
 @param frameGenerator the Frame Generator to register with.
 @param logger the logger object to log events to, may be nil.
 @param eventSink an event sink to report video output to.
 @return a new FBFramebufferVideo instance.
 */
+ (instancetype)videoWithConfiguration:(FBVideoEncoderConfiguration *)configuration frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink;

/**
 The Designated Initializer.

 @param configuration the configuration to use for encoding.
 @param surface the Renderable to Record.
 @param logger the logger object to log events to, may be nil.
 @param eventSink an event sink to report video output to.
 @return a new FBFramebufferVideo instance.
 */
+ (instancetype)videoWithConfiguration:(FBVideoEncoderConfiguration *)configuration surface:(FBFramebufferSurface *)surface logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink;

/**
 YES if Surface Based Supporting is available, NO otherwise.
 */
+ (BOOL)surfaceSupported;

@end

NS_ASSUME_NONNULL_END

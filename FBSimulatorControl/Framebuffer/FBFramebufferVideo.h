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
@class FBFramebufferRenderable;
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
 An implementation of FBFramebufferVideo, using FBVideoEncoderBuiltIn.
 */
@interface FBFramebufferVideo_BuiltIn : NSObject <FBFramebufferVideo>

/**
 The Designated Initializer.

 @param configuration the configuration to use for encoding.
 @param frameGenerator the Frame Generator to register with.
 @param logger the logger object to log events to, may be nil.
 @param eventSink an event sink to report video output to.
 @return a new FBFramebufferVideo instance.
 */
+ (instancetype)videoWithConfiguration:(FBVideoEncoderConfiguration *)configuration frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink;

@end

/**
 An implementation of FBFramebufferVideo, using FBVideoEncoderSimulatorKit
 */
@interface FBFramebufferVideo_SimulatorKit : NSObject <FBFramebufferVideo>

/**
 The Designated Initializer.

 @param configuration the configuration to use for encoding.
 @param renderable the Renderable to Record.
 @param logger the logger object to log events to, may be nil.
 @param eventSink an event sink to report video output to.
 @return a new FBFramebufferVideo instance.
 */
+ (instancetype)videoWithConfiguration:(FBVideoEncoderConfiguration *)configuration renderable:(FBFramebufferRenderable *)renderable logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink;

/**
 YES if this class is supported, NO otherwise.
 */
+ (BOOL)isSupported;

@end

NS_ASSUME_NONNULL_END

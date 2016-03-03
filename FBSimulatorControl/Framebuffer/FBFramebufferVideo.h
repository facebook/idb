/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBFramebufferDelegate.h>

@class FBFramebufferVideoConfiguration;
@protocol FBSimulatorLogger;
@protocol FBSimulatorEventSink;

/**
 A Simulator Framebuffer Delegate that encodes video and writes to a file.

 All media activity is serialized on a queue, this queue is internal and should not be used by clients.
 The video will be created as soon as the first frame is available.
 */
@interface FBFramebufferVideo : NSObject <FBFramebufferDelegate>

/**
 Creates a new FBFramebufferVideo instance.

 @param configuration the configuration to use for encoding.
 @param logger the logger object to log events to, may be nil.
 @param eventSink an event sink to report video output to.
 @return a new FBFramebufferVideo instance.
 */
+ (instancetype)withConfiguration:(FBFramebufferVideoConfiguration *)configuration logger:(id<FBSimulatorLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink;

/**
 Starts Recording Video.
 If the video is already recording, this call will do nothing.
 Is asynchronous with the caller so the Event Sink will be notified when the video starts recording.
 */
- (void)startRecording;

/**
 Stops Recording Video.
 If the video is not recording, this call will do nothing.
 Is asynchronous with the caller so the Event Sink will be notified when the video starts recording.
 */
- (void)stopRecording;

@end

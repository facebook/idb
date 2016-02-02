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

@class FBDiagnostic;
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

 @param diagnostic the log to base the video file from.
 @param scale the scaling factor of the video. Must be 1 or lower.
 @param logger the logger object to log events to, may be nil.
 @param eventSink an event sink to report video output to.
 @return a new FBFramebufferVideo instance.
 */
+ (instancetype)withWritableLog:(FBDiagnostic *)diagnostic scale:(CGFloat)scale logger:(id<FBSimulatorLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink;

/**
 Stops the recording recording of the video framebuffer.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)stopRecordingWithError:(NSError **)error;

@end

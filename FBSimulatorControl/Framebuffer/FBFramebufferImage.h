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
@protocol FBSimulatorEventSink;

/**
 A Simulator Framebuffer Delegate that stores an image of the most recent image.

 When a Framebuffer is torn down, all it's delegates will be too.
 Just as this occurs, this class will report the image to the Event Sink.
 This means that the final frame will be captured.
 */
@interface FBFramebufferImage : NSObject <FBFramebufferDelegate>

/**
 Creates a new FBFramebufferImage instance.

 @param diagnostic the Diagnostic to base image reporting off.
 @param eventSink the Event Sink to report Image Logs to.
 @return a new FBFramebufferImage instance.
 */
+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic eventSink:(id<FBSimulatorEventSink>)eventSink;

/**
 Writes a PNG to file and updates the Diagnostic.

 @param image the image to update the log with.
 @param diagnostic the log to base the new log off.
 @return a new FBDiagnostic with a path to the image on succcess, the original log on failure.
 */
+ (FBDiagnostic *)appendImage:(CGImageRef)image toDiagnostic:(FBDiagnostic *)diagnostic;

/**
 The Latest Image from the Framebuffer.
 */
@property (atomic, assign, readonly) CGImageRef image;

@end

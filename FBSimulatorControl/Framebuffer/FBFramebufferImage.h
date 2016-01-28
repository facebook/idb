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

@class FBWritableLog;
@protocol FBSimulatorEventSink;

/**
 A Simulator Framebuffer Delegate that stores an image of the most recent image.
 
 When a Framebuffer is teared down, all it's delegates will be too.
 Just as this occurs, this class will report the image to the Event Sink.
 This means that the final frame will be captured.
 */
@interface FBFramebufferImage : NSObject <FBFramebufferDelegate>

/**
 Creates a new FBFramebufferImage instance.
 
 @param writableLog the Writable Log to base image reporting off.
 @param eventSink the Event Sink to report Image Logs to.
 @return a new FBFramebufferImage instance.
 */
+ (instancetype)withWritableLog:(FBWritableLog *)writableLog eventSink:(id<FBSimulatorEventSink>)eventSink;

/**
 Writes a PNG to file and updates the Writable Log.

 @param image the image to update the log with.
 @param writableLog the log to base the new log off.
 @return a new FBWritableLog with a path to the image on succcess, the original log on failure.
 */
+ (FBWritableLog *)appendImage:(CGImageRef)image toWritableLog:(FBWritableLog *)writableLog;

/**
 The Latest Image from the Framebuffer.
 */
@property (atomic, assign, readonly) CGImageRef image;

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBFramebufferFrameSink.h>

@class FBDiagnostic;
@class SimDeviceIOClient;
@protocol FBSimulatorEventSink;

NS_ASSUME_NONNULL_BEGIN

/**
 A Protocol providing access to an Image Representation of the Framebuffer
 */
@protocol FBFramebufferImage <NSObject>

/**
 The Latest Image from the Framebuffer.
 This will return an autorelease Image, so it should be retained by the caller.
 */
- (nullable CGImageRef)image;

/**
 Get a JPEG encoded representation of the Image.

 @param error an error out for any error that occurs.
 @return the data if successful, nil otherwise.
 */
- (nullable NSData *)jpegImageDataWithError:(NSError **)error;

/**
 Get a PNG encoded representation of the Image.

 @param error an error out for any error that occurs.
 @return the data if successful, nil otherwise.
 */
- (nullable NSData *)pngImageDataWithError:(NSError **)error;

@end

/**
 A FBFramebufferImage Implementation using FBFramebufferFrameSink.

 When a Framebuffer is torn down, all it's delegates will be too.
 Just as this occurs, this class will report the image to the Event Sink.
 This means that the final frame will be captured.
 */
@interface FBFramebufferImage_FrameSink : NSObject <FBFramebufferImage, FBFramebufferFrameSink>

/**
 Creates a new FBFramebufferImage instance.

 @param diagnostic the Diagnostic to base image reporting off.
 @param eventSink the Event Sink to report Image Logs to.
 @return a new FBFramebufferImage instance.
 */
+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic eventSink:(id<FBSimulatorEventSink>)eventSink;

@end

/**
 A FBFramebufferImage Implementation using SimulatorKit
 */
@interface FBFramebufferImage_Surface : NSObject <FBFramebufferImage>

/**
 Creates a new FBFramebufferImage instance.

 @param diagnostic the Diagnostic to base image reporting off.
 @param eventSink the Event Sink to report Image Logs to.
 @return a new FBFramebufferImage instance.
 */
+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic eventSink:(id<FBSimulatorEventSink>)eventSink ioClient:(SimDeviceIOClient *)ioClient;

@end

NS_ASSUME_NONNULL_END

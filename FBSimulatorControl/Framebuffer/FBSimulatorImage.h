/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBFramebufferSurface.h>

@class FBDiagnostic;
@class FBFramebufferFrameGenerator;
@class FBFramebufferSurface;
@protocol FBSimulatorEventSink;

NS_ASSUME_NONNULL_BEGIN

/**
 Provides access to an Image Representation of a Simulator's Framebuffer.
 */
@interface FBSimulatorImage : NSObject

#pragma mark Initializers

/**
 Creates a new FBSimulatorImage instance using a Frame Generator.

 @param filePath the File Path to write to.
 @param frameGenerator the Frame Generator to register with.
 @param eventSink the Event Sink to report Image Logs to.
 @return a new FBSimulatorImage instance.
 */
+ (instancetype)imageWithFilePath:(NSString *)filePath frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator eventSink:(id<FBSimulatorEventSink>)eventSink;

/**
 Creates a new FBSimulatorImage instance using a Surface.

 @param filePath the File Path to write to.
 @param surface the surface to obtain frames from.
 @param eventSink the Event Sink to report Image Logs to.
 @return a new FBSimulatorImage instance.
 */
+ (instancetype)imageWithFilePath:(NSString *)filePath surface:(FBFramebufferSurface *)surface eventSink:(id<FBSimulatorEventSink>)eventSink;

#pragma mark Public Methods

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

NS_ASSUME_NONNULL_END

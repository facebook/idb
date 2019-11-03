/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBFramebuffer.h>

NS_ASSUME_NONNULL_BEGIN

@class FBFramebuffer;
@protocol FBSimulatorEventSink;

/**
 Provides access to an Image Representation of a Simulator's Framebuffer.
 */
@interface FBSimulatorImage : NSObject

#pragma mark Initializers

/**
 Creates a new FBSimulatorImage instance using a Surface.

 @param framebuffer the framebuffer to obtain frames from.
 @param logger the logger to use.
 @return a new FBSimulatorImage instance.
 */
+ (instancetype)imageWithFramebuffer:(FBFramebuffer *)framebuffer logger:(nullable id<FBControlCoreLogger>)logger;

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

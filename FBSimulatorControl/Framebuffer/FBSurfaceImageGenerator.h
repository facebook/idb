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

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;

/**
 An object-container for an IOSurface, that can generate Images.
 */
@interface FBSurfaceImageGenerator : NSObject <FBFramebufferSurfaceConsumer>

/**
 Create and return a new Image Generator.

 @param scale the scale to use for the Image.
 @param logger the logger to use.
 @return a new Image Generator.
 */
+ (instancetype)imageGeneratorWithScale:(NSDecimalNumber *)scale logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Return a CGImageRef.
 The Image returned is autoreleased, so the caller must retain it.

 If there is no new image since the last time this was called, NULL will be returned.
 When when this image is obtained, it will be considered 'consumed'
 */
- (nullable CGImageRef)availableImage;

/**
 Return a CGImageRef.
 The Image returned is autoreleased, so the caller must retain it.

 This will not 'consume' the Image and can be fetched regardless of the last image consumed.
 */
- (nullable CGImageRef)image;

@end

NS_ASSUME_NONNULL_END

/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBFramebuffer.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;

/**
 An object-container for an IOSurface, that can generate Images.
 */
@interface FBSurfaceImageGenerator : NSObject <FBFramebufferConsumer>

/**
 Create and return a new Image Generator.

 @param scale the scale to use for the Image.
 @param purpose the pupose of the image generator.
 @param logger the logger to use.
 @return a new Image Generator.
 */
+ (instancetype)imageGeneratorWithScale:(NSDecimalNumber *)scale purpose:(NSString *)purpose logger:(nullable id<FBControlCoreLogger>)logger;

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

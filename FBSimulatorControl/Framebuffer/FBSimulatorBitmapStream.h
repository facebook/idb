/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControl/FBFramebufferSurface.h>

NS_ASSUME_NONNULL_BEGIN

@class FBFramebufferSurface;
@protocol FBFileConsumer;
@protocol FBControlCoreLogger;

/**
 A Bitmap Stream of a Simulator's Framebuffer.
 This component can be used to provide a real-time stream of a Simulator's Framebuffer.
 This can be connected to additional software via a stream to a File Handle or Fifo.
 */
@interface FBSimulatorBitmapStream : NSObject <FBFramebufferSurfaceConsumer, FBBitmapStream>

#pragma mark Initializers

/**
 Constructs a Bitmap Stream.
 Bitmaps will only be written when there is a new bitmap available.

 @param surface the surface to connect to.
 @param logger the logger to log to.
 @return a new Bitmap Stream object.
 */
+ (instancetype)lazyStreamWithSurface:(FBFramebufferSurface *)surface logger:(id<FBControlCoreLogger>)logger;

/**
 Constructs a Bitmap Stream.
 Bitmaps will be written at an interval in seconds, regardless of whether the frame is new or not.

 @param surface the surface to connect to.
 @param framesPerSecond the number of frames to send per second.
 @param logger the logger to log to.
 @return a new Bitmap Stream object.
 */
+ (instancetype)eagerStreamWithSurface:(FBFramebufferSurface *)surface framesPerSecond:(NSUInteger)framesPerSecond logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END

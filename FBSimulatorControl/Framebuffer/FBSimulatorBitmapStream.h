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

#import <FBSimulatorControl/FBFramebuffer.h>

NS_ASSUME_NONNULL_BEGIN

@class FBFramebuffer;
@protocol FBFileConsumer;
@protocol FBControlCoreLogger;

/**
 A Bitmap Stream of a Simulator's Framebuffer.
 This component can be used to provide a real-time stream of a Simulator's Framebuffer.
 This can be connected to additional software via a stream to a File Handle or Fifo.
 */
@interface FBSimulatorBitmapStream : NSObject <FBFramebufferConsumer, FBBitmapStream>

#pragma mark Initializers

/**
 Constructs a Bitmap Stream.
 Bitmaps will only be written when there is a new bitmap available.

 @param framebuffer the framebuffer to get frames from.
 @param logger the logger to log to.
 @return a new Bitmap Stream object.
 */
+ (instancetype)lazyStreamWithFramebuffer:(FBFramebuffer *)framebuffer logger:(id<FBControlCoreLogger>)logger;

/**
 Constructs a Bitmap Stream.
 Bitmaps will be written at an interval in seconds, regardless of whether the frame is new or not.

 @param framebuffer the framebuffer to get frames from.
 @param framesPerSecond the number of frames to send per second.
 @param logger the logger to log to.
 @return a new Bitmap Stream object.
 */
+ (instancetype)eagerStreamWithFramebuffer:(FBFramebuffer *)framebuffer framesPerSecond:(NSUInteger)framesPerSecond logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END

/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControl/FBFramebuffer.h>

NS_ASSUME_NONNULL_BEGIN

@class FBFramebuffer;
@protocol FBDataConsumer;
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
 @param encoding the encoding to use.
 @param logger the logger to log to.
 @param error an error out for any error that occurs
 @return a new Bitmap Stream object, nil on failure
 */
+ (nullable instancetype)lazyStreamWithFramebuffer:(FBFramebuffer *)framebuffer encoding:(FBBitmapStreamEncoding)encoding logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;

/**
 Constructs a Bitmap Stream.
 Bitmaps will be written at an interval in seconds, regardless of whether the frame is new or not.

 @param framebuffer the framebuffer to get frames from.
 @param encoding the encoding to use.
 @param framesPerSecond the number of frames to send per second.
 @param logger the logger to log to.
 @return a new Bitmap Stream object, nil on failure.
 */
+ (nullable instancetype)eagerStreamWithFramebuffer:(FBFramebuffer *)framebuffer encoding:(FBBitmapStreamEncoding)encoding framesPerSecond:(NSUInteger)framesPerSecond logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

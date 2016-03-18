/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

/**
 An NSObject Container for a Framebuffer's Frame.
 */
@interface FBFramebufferFrame : NSObject

@property (nonatomic, assign, readonly) CMTime time;
@property (nonatomic, assign, readonly) CMTimebaseRef timebase;
@property (nonatomic, assign, readonly) NSUInteger count;
@property (nonatomic, assign, readonly) CGImageRef image;
@property (nonatomic, assign, readonly) CGSize size;

/**
 The Designated Initializer.

 @param time the time the frame was recieved.
 @param timebase the timebase the time was constructed with.
 @param image the image data of the frame.
 @param count the ordering of the frame in all frames.
 @param size the size of the image.
 */
- (instancetype)initWithTime:(CMTime)time timebase:(CMTimebaseRef)timebase image:(CGImageRef)image count:(NSUInteger)count size:(CGSize)size;

/**
 Constructs a new FBFramebufferFrame by translating it to a destination timebase and scale.

 @param destinationTimebase the timebase to convert to.
 @param timescale the Timescale to convert to.
 @param roundingMethod the rounding method to use.
 @return a new FBFramebufferFrame in the destination timebase.
 */
- (instancetype)convertToTimebase:(CMTimebaseRef)destinationTimebase timescale:(CMTimeScale)timescale roundingMethod:(CMTimeRoundingMethod)roundingMethod;

/**
 Constructs a new FBFramebufferFrame by updating it with the current time.
 This is useful if you wish to 'repeat' a historical frame.

 @param timebase the Timebase to get the time from.
 @param timescale the Timescale to convert to.
 @param roundingMethod the rounding method to use.
 @return a new FBFramebufferFrame in the destination timebase.
 */
- (instancetype)updateWithCurrentTimeInTimebase:(CMTimebaseRef)timebase timescale:(CMTimeScale)timescale roundingMethod:(CMTimeRoundingMethod)roundingMethod;

@end

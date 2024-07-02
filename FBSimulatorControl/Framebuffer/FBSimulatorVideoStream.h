/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControl/FBFramebuffer.h>

NS_ASSUME_NONNULL_BEGIN

@class FBFramebuffer;
@class FBVideoStreamConfiguration;
@protocol FBDataConsumer;
@protocol FBDataConsumerSync;
@protocol FBDataConsumerAsync;
@protocol FBControlCoreLogger;

/**
 A Video Stream of a Simulator's Framebuffer.
 This component can be used to provide a real-time stream of a Simulator's Framebuffer.
 This can be connected to additional software via a stream to a File Handle or Fifo.
 */
@interface FBSimulatorVideoStream : NSObject <FBFramebufferConsumer, FBVideoStream>

#pragma mark Initializers

/**
 Constructs a Bitmap Stream.
 Bitmaps will only be written when there is a new bitmap available.

 @param framebuffer the framebuffer to get frames from.
 @param configuration the configuration to use.
 @param logger the logger to log to.
 @return a new Bitmap Stream object, nil on failure
 */
+ (nullable instancetype)streamWithFramebuffer:(FBFramebuffer *)framebuffer configuration:(FBVideoStreamConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END

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

/**
 Builds the compression session properties dictionary for a given configuration and caller-provided properties.
 This is extracted for testability — the dictionary is passed to VTSessionSetProperties at stream start.

 @param configuration the stream configuration (encoding, quality, bitrate, etc.).
 @param callerProperties additional properties from the stream subclass (e.g. FPS-related keys for eager streams).
 @return an immutable dictionary of compression session properties.
 */
+ (NSDictionary<NSString *, id> *)compressionSessionPropertiesForConfiguration:(FBVideoStreamConfiguration *)configuration callerProperties:(NSDictionary<NSString *, id> *)callerProperties;

#pragma mark Overlay

/**
 Update the overlay buffer and push a frame to encode the change.
 The buffer should be BGRA with premultiplied alpha, ideally IOSurface-backed for zero-copy GPU compositing.
 Pass the same buffer reference after updating its contents in-place, or a new buffer to swap.
 Pass nil to clear the overlay.

 In lazy/VFR mode: dispatches pushFrame on the write queue so overlay changes are encoded immediately.
 In eager/CFR mode: no extra push — the next cadence tick picks up the change without disrupting frame timing.

 @param overlayBuffer a CVPixelBuffer with the overlay content, or nil to clear.
 */
- (void)updateOverlayBuffer:(nullable CVPixelBufferRef)overlayBuffer;

@end

NS_ASSUME_NONNULL_END

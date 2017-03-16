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

NS_ASSUME_NONNULL_BEGIN

@class FBFramebufferConfiguration;
@class FBFramebufferSurface;
@class FBSimulator;
@class FBSimulatorImage;
@class FBSimulatorVideo;
@class SimDeviceFramebufferService;
@protocol FBFramebufferFrameSink;
@protocol FBFramebufferSurfaceConsumer;

/**
 A container and client for a Simulator's Framebuffer.
 The Framebuffer is a representation of a Simulator's Screen, exposed as public API.
 By default there are the default 'video' and 'image' components that allow access to a video encoder and image representation respectively.

 It is also possible to attach to a Framebuffer in two ways:
 1) Connecting using an FBFramebufferSurfaceConsumer. This allows consumption of an IOSurface backing the Simulator as well as events for damage rectangles.
 2) Connecting using a FBFramebufferFrameSink. This will internally generate an FBFramebufferFrame object, suitable for further consumption.
 */
@interface FBFramebuffer : NSObject <FBJSONSerializable>

#pragma mark Initializers

/**
 Creates and returns a FBFramebuffer.

 @param framebufferService the SimDeviceFramebufferService to connect to.
 @param configuration the configuration of the Framebuffer.
 @param simulator the Simulator to which the Framebuffer belongs.
 @return a new FBSimulatorDirectLaunch instance. Must not be nil.
 */
+ (instancetype)framebufferWithService:(SimDeviceFramebufferService *)framebufferService configuration:(FBFramebufferConfiguration *)configuration simulator:(FBSimulator *)simulator;

/**
 Creates and returns a FBFramebuffer.

 @param surface the Renderable to connect to.
 @param configuration the configuration of the Framebuffer.
 @param simulator the Simulator to which the Framebuffer belongs.
 @return a new FBSimulatorDirectLaunch instance. Must not be nil.
 */
+ (instancetype)framebufferWithRenderable:(FBFramebufferSurface *)surface configuration:(FBFramebufferConfiguration *)configuration simulator:(FBSimulator *)simulator;

#pragma mark Public Methods

/**
 Causes the Framebuffer to Tear Down.
 Must only be called from the main queue.
 A dispatch_group is provided to allow for delegates to append any asychronous operations that may need cleanup.
 For example in the case of the Video Recorder, this means completing the writing to file.

 @param teardownGroup the dispatch_group to append asynchronous operations to.
 */
- (void)teardownWithGroup:(dispatch_group_t)teardownGroup;

/**
 Attaches a Frame Sink

 @param frameSink the Frame Sink to attach.
 */
- (void)attachFrameSink:(id<FBFramebufferFrameSink>)frameSink;

/**
 Detaches a Frame Sink

 @param frameSink the Frame Sink to detach.
 */
- (void)detachFrameSink:(id<FBFramebufferFrameSink>)frameSink;

#pragma mark Properties

/**
 The FBSimulatorVideo instance owned by the receiver.
 */
@property (nonatomic, strong, readonly) FBSimulatorVideo *video;

/**
 The FBSimulatorImage instance owned by the receiver.
 */
@property (nonatomic, strong, readonly) FBSimulatorImage *image;

/**
 The FBFramebufferSurface owned by the reciever, if supported.
 */
@property (nonatomic, strong, nullable, readonly) FBFramebufferSurface *surface;

@end

NS_ASSUME_NONNULL_END

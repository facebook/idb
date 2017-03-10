/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <IOSurface/IOSurface.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControl/FBFramebufferSurface.h>

@protocol FBFramebufferFrameSink;
@class FBFramebufferFrame;
@class SimDeviceFramebufferBackingStore;

NS_ASSUME_NONNULL_BEGIN

/**
 Generates Frames from a Simulator's Framebuffer.
 This class is abstract, use FBFramebufferBackingStoreFrameGenerator or FBFramebufferIOSurfaceFrameGenerator as appropriate.
 This is provided for compatability with older versions of Xcode. Using FBFramebufferSurface directly is far more efficient.

 Frame Sinks can be attached to register interest in recieving Frames.
 A Frame Generator is completely inert until a consumer is attached in 'attachSink:'.
 */
@interface FBFramebufferFrameGenerator : NSObject <FBJSONSerializable>

#pragma mark Public Properties

/**
 Attaches a Sink to the Frame Generator.

 @param sink the Sink to Attach.
 */
- (void)attachSink:(id<FBFramebufferFrameSink>)sink;

/**
 Attaches a Sink to the Frame Generator.

 @param sink the Sink to detach.
 */
- (void)detachSink:(id<FBFramebufferFrameSink>)sink;

/**
 Tears down the Frame Generator, notifying all sinks.

 @param teardownGroup a dispatch_group to add asynchronous tasks to that should be performed in the teardown of the Framebuffer.
 */
- (void)teardownWithGroup:(dispatch_group_t)teardownGroup;

@end

/**
 A Frame Generator for Xcode 7's 'SimDeviceFramebufferService'.
 */
@interface FBFramebufferBackingStoreFrameGenerator : FBFramebufferFrameGenerator

#pragma mark Initializers

/**
 Creates and returns a new Generator for the Xcode 7 'SimDeviceFramebufferBackingStore'.

 @param service the Framebuffer Service
 @param scale the Scale Factor.
 @param queue the Queue that attached sinks will be notified on.
 @param logger the logger to log to.
 @return a new Framebuffer Frame Generator.
 */
+ (instancetype)generatorWithFramebufferService:(SimDeviceFramebufferService *)service scale:(NSDecimalNumber *)scale queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

@end

/**
 A Frame Generator for the an IOSurface reprentation, available in Xcode 8 or greater.
 */
@interface FBFramebufferIOSurfaceFrameGenerator : FBFramebufferFrameGenerator <FBFramebufferSurfaceConsumer>

/**
 Creates and returns a new Generator for FBFramebufferSurface.

 @param surface the surface to connect to.
 @param scale the Scale Factor.
 @param queue the Queue that attached sinks will be notified on.
 @param logger the logger to log to.
 @return a new Framebuffer Frame Generator.
 */
+ (instancetype)generatorWithRenderable:(FBFramebufferSurface *)surface scale:(NSDecimalNumber *)scale queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

@end

/**
 A reciever of Frames, connected to a FBFramebufferFrameGenerator.
 */
@protocol FBFramebufferFrameSink <NSObject>

/**
 Called when an Image Frame is available.

 @param frameGenerator the frame generator.
 @param frame the updated frame.
 */
- (void)frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator didUpdate:(FBFramebufferFrame *)frame;

/**
 Called when the framebuffer is no longer valid, typically when the Simulator shuts down.

 @param frameGenerator the frame generator.
 @param error an error, if any occured in the teardown of the simulator.
 @param teardownGroup a dispatch_group to add asynchronous tasks to that should be performed in the teardown of the Framebuffer.
 */
- (void)frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator didBecomeInvalidWithError:(nullable NSError *)error teardownGroup:(dispatch_group_t)teardownGroup;

@end

NS_ASSUME_NONNULL_END

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SimDeviceIOClient;
@class SimDeviceFramebufferService;
@protocol SimDisplayDamageRectangleDelegate;
@protocol SimDisplayIOSurfaceRenderableDelegate;
@protocol SimDeviceIOPortConsumer;

/**
 A Consumer of a Renderable.
 */
@protocol FBFramebufferRenderableConsumer <NSObject>

/**
 Called when an IOSurface becomes available or invalid
 
 @param surface the surface, or NULL if a surface is not available/becomes unavailable
 */
- (void)didChangeIOSurface:(nullable IOSurfaceRef)surface;

/**
 When a Damage Rect becomes available.
 
 @param rect the damage rectangle.
 */
- (void)didReceiveDamageRect:(CGRect)rect;

/**
 The Identifier of the Consumer.
 */
@property (nonatomic, copy, readonly) NSString *consumerIdentifier;

@end

/**
 A Container Object for a Renderable IOSurface Client.
 Adapts IOSurface fetching to a common protocol.
 */
@interface FBFramebufferRenderable : NSObject

/**
 Obtains the Renderable from the Client.

 @param ioClient the IOClient to attach to.
 @prarm delegate the delegate to attach.
 @return a Port Interface, should be retained by the reciever.
 */
+ (nullable instancetype)mainScreenRenderableForClient:(SimDeviceIOClient *)ioClient;

/**
 Obtains an IOSurface froma FramebufferService.

 @param framebufferService the Framebuffer Service to obtain from.
 @param clientQueue the queue to schedule work on.
 @return a Service Client.
 */
+ (instancetype)mainScreenRenderableForFramebufferService:(SimDeviceFramebufferService *)framebufferService clientQueue:(dispatch_queue_t)clientQueue;

/**
 Attaches a Consumer with the Renderable

 @param consumer the consumer to attach.
 */
- (void)attachConsumer:(id<FBFramebufferRenderableConsumer>)consumer;

/**
 Detaches a Consumer with the Renderable

 @param consumer the consumer to attach.
 */
- (void)detachConsumer:(id<FBFramebufferRenderableConsumer>)consumer;

@end

NS_ASSUME_NONNULL_END

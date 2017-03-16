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
 A Consumer of a Surface.
 */
@protocol FBFramebufferSurfaceConsumer <NSObject>

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
 Provides Surfaces to interested consumers, wrapping the underlying implementation.
 */
@interface FBFramebufferSurface : NSObject

/**
 Obtains an IOSurface from the SimDeviceIOClient.

 @param ioClient the IOClient to attach to.
 @return a new FBFramebufferSurface.
 */
+ (nullable instancetype)mainScreenSurfaceForClient:(SimDeviceIOClient *)ioClient;

/**
 Obtains an IOSurface from the SimDeviceFramebufferService.

 @param framebufferService the Framebuffer Service to obtain from.
 @param clientQueue the queue to schedule work on.
 @return a new FBFramebufferSurface.
 */
+ (instancetype)mainScreenSurfaceForFramebufferService:(SimDeviceFramebufferService *)framebufferService clientQueue:(dispatch_queue_t)clientQueue;

/**
 Attaches a Consumer.

 @param consumer the consumer to attach.
 */
- (void)attachConsumer:(id<FBFramebufferSurfaceConsumer>)consumer;

/**
 Detaches a Consumer.

 @param consumer the consumer to attach.
 */
- (void)detachConsumer:(id<FBFramebufferSurfaceConsumer>)consumer;

/**
 An Array of all attached consumers
 */
- (NSArray<id<FBFramebufferSurfaceConsumer>> *)attachedConsumers;

@end

NS_ASSUME_NONNULL_END

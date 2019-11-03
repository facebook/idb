/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class SimDeviceFramebufferService;
@class SimDeviceIOClient;

@protocol SimDisplayDamageRectangleDelegate;
@protocol SimDisplayIOSurfaceRenderableDelegate;
@protocol SimDeviceIOPortConsumer;

/**
 A Consumer of a Framebuffer.
 */
@protocol FBFramebufferConsumer <NSObject>

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
 Provides a Framebuffer to interested consumers, wrapping the underlying implementation.
 */
@interface FBFramebuffer : NSObject <FBJSONSerializable>

#pragma mark Initializers

/**
 Obtains an IOSurface from the SimDeviceIOClient.

 @param ioClient the IOClient to attach to.
 @param logger the logger to log to.
 @return a new FBFramebuffer.
 */
+ (nullable instancetype)mainScreenSurfaceForClient:(SimDeviceIOClient *)ioClient logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;

/**
 Obtains an IOSurface from the SimDeviceFramebufferService.

 @param framebufferService the Framebuffer Service to obtain from.
 @param logger the logger to log to.
 @return a new FBFramebuffer.
 */
+ (instancetype)mainScreenSurfaceForFramebufferService:(SimDeviceFramebufferService *)framebufferService logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Attaches a Consumer.
 The Consumer will be called on the provided queue.

 @param consumer the consumer to attach.
 @param queue the queue to notify the consumer on.
 @return A Surface is one is *immediately* available. This is not mutually exclusive the consumer being called on a queue.
 */
- (nullable IOSurfaceRef)attachConsumer:(id<FBFramebufferConsumer>)consumer onQueue:(dispatch_queue_t)queue;

/**
 Detaches a Consumer.
 The Consumer will be called on the provided queue.

 @param consumer the consumer to attach.
 */
- (void)detachConsumer:(id<FBFramebufferConsumer>)consumer;

/**
 An Array of all attached consumers
 */
- (NSArray<id<FBFramebufferConsumer>> *)attachedConsumers;

/**
 Queries if the consumer is attached.

 @param consumer the consumer to use.
 @return YES if attached, NO otherwise.
 */
- (BOOL)isConsumerAttached:(id<FBFramebufferConsumer>)consumer;

@end

NS_ASSUME_NONNULL_END

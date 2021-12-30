/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class IOSurface;

/**
 A Consumer of a Framebuffer.
 */
@protocol FBFramebufferConsumer <NSObject>

/**
 Called when an IOSurface becomes available or invalid

 @param surface the surface, or NULL if a surface is not available/becomes unavailable
 */
- (void)didChangeIOSurface:(nullable IOSurface *)surface;

/**
 When a Damage Rect becomes available.

 @param rect the damage rectangle.
 */
- (void)didReceiveDamageRect:(CGRect)rect;

@end

/**
 Provides a Framebuffer to interested consumers, wrapping the underlying implementation.
 */
@interface FBFramebuffer : NSObject

#pragma mark Initializers

/**
 Obtains an IOSurface from the SimDeviceIOClient.

 @param simulator the IOClient to attach to.
 @param logger the logger to log to.
 @param error an error out for any error that occurs.
 @return a new FBFramebuffer if one could be constructed, nil on error.
 */
+ (nullable instancetype)mainScreenSurfaceForSimulator:(FBSimulator *)simulator logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;

#pragma mark Public Methods

/**
 Attaches a Consumer.
 The Consumer will be called on the provided queue.

 @param consumer the consumer to attach.
 @param queue the queue to notify the consumer on.
 @return A Surface is one is *immediately* available. This is not mutually exclusive the consumer being called on a queue.
 */
- (nullable IOSurface *)attachConsumer:(id<FBFramebufferConsumer>)consumer onQueue:(dispatch_queue_t)queue;

/**
 Detaches a Consumer.
 The Consumer will be called on the provided queue.

 @param consumer the consumer to attach.
 */
- (void)detachConsumer:(id<FBFramebufferConsumer>)consumer;

/**
 Queries if the consumer is attached.

 @param consumer the consumer to use.
 @return YES if attached, NO otherwise.
 */
- (BOOL)isConsumerAttached:(id<FBFramebufferConsumer>)consumer;

@end

NS_ASSUME_NONNULL_END

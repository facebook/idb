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

@class SimDeviceFramebufferService;
@class SimDeviceIOClient;

/**
 Obtains an IOSurface from SimulatorKit.
 */
@interface FBFramebufferSurfaceClient : NSObject

/**
 Obtains an IOSurface froma FramebufferService.

 @param framebufferService the Framebuffer Service to obtain from.
 @param clientQueue the queue to schedule work on.
 @return a Service Client.
 */
+ (instancetype)clientForFramebufferService:(SimDeviceFramebufferService *)framebufferService clientQueue:(dispatch_queue_t)clientQueue;

/**
 Obtains an IOSurface from an IOClient.

 @param ioClient the Framebuffer Service to obtain from.
 @param clientQueue the queue to schedule work on.
 @return a Service Client.
 */
+ (instancetype)clientForIOClient:(SimDeviceIOClient *)ioClient clientQueue:(dispatch_queue_t)clientQueue;

/**
 Obtains the Surface

 @param callback the callback to obtain the surface on.
 */
- (void)obtainSurface:(void (^)(IOSurfaceRef))callback;

/**
 Cleans Up the connection to the IOSurface.
 */
- (void)detach;

/**
 Convenience method for detatching from a Framebuffer Service.

 @param framebufferService the Framebuffer Service to detach from.
 */
+ (void)detachFromFramebufferService:(SimDeviceFramebufferService *)framebufferService;

@end

NS_ASSUME_NONNULL_END

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
@protocol SimDisplayDamageRectangleDelegate;
@protocol SimDisplayIOSurfaceRenderableDelegate;
@protocol SimDeviceIOPortConsumer;

/**
 A Container Object for a Renderable IOSurface Client.
 */
@interface FBFramebufferRenderable : NSObject

/**
 Obtains the Renderable from the Client.

 @param ioClient the IOClient to attach to.
 @prarm delegate the delegate to attach.
 @return a Port Interface, should be retained by the reciever.
 */
+ (instancetype)mainScreenRenderableForClient:(SimDeviceIOClient *)ioClient;

/**
 Attaches a Consumer with the Renderable

 @param consumer the consumer to attach.
 */
- (void)attachConsumer:(id<SimDisplayDamageRectangleDelegate, SimDisplayIOSurfaceRenderableDelegate, SimDeviceIOPortConsumer>)consumer;

/**
 Detaches a Consumer with the Renderable

 @param consumer the consumer to attach.
 */
- (void)detachConsumer:(id<SimDisplayDamageRectangleDelegate, SimDisplayIOSurfaceRenderableDelegate, SimDeviceIOPortConsumer>)consumer;

@end

NS_ASSUME_NONNULL_END

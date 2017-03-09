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
@class FBFramebufferRenderable;
@class FBSimulator;
@class SimDeviceFramebufferService;
@protocol FBFramebufferFrameSink;
@protocol FBFramebufferVideo;
@protocol FBFramebufferImage;

/**
 A container and client for a Simulator's Framebuffer.
 The Framebuffer is a representation of a Simulator's Screen, exposed as public API.
 By default there are the default 'video' and 'image' components that allow access to a video encoder and image representation respectively.
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

 @param renderable the Renderable to connect to.
 @param configuration the configuration of the Framebuffer.
 @param simulator the Simulator to which the Framebuffer belongs.
 @return a new FBSimulatorDirectLaunch instance. Must not be nil.
 */
+ (instancetype)framebufferWithRenderable:(FBFramebufferRenderable *)renderable configuration:(FBFramebufferConfiguration *)configuration simulator:(FBSimulator *)simulator;

#pragma mark Public Methods

/**
 Causes the Framebuffer to Tear Down.
 Must only be called from the main queue.
 A dispatch_group is provided to allow for delegates to append any asychronous operations that may need cleanup.
 For example in the case of the Video Recorder, this means completing the writing to file.

 @param teardownGroup the dispatch_group to append asynchronous operations to.
 */
- (void)teardownWithGroup:(dispatch_group_t)teardownGroup;

#pragma mark Properties

/**
 The FBFramebufferVideo instance owned by the receiver.
 */
@property (nonatomic, strong, readonly) id<FBFramebufferVideo> video;

/**
 The FBFramebufferImage instance owned by the receiver.
 */
@property (nonatomic, strong, readonly) id<FBFramebufferImage> image;

@end

NS_ASSUME_NONNULL_END

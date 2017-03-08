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

@protocol FBFramebufferFrameSink;
@class FBFramebuffer;
@class SimDeviceFramebufferBackingStore;

NS_ASSUME_NONNULL_BEGIN

/**
 Generates Image Frames Objects and forwards them to the a sink.
 This class is abstract, use FBFramebufferBackingStoreFrameGenerator or FBFramebufferIOSurfaceFrameGenerator as appropriate.
 This is provided for compatability with older versions of Xcode. Using IOSurface directly is far more efficient.
 */
@interface FBFramebufferFrameGenerator : NSObject <FBJSONSerializable>

#pragma mark Public Intializers

/**
 Creates and returns a new Generator.
 Must be called on the subclasses of FBFramebufferFrameGenerator.

 @param scale the Scale Factor.
 @param sink the reciever of Frames.
 @param queue the Queue the Delegate will be called on.
 @param logger the logger to log to.
 @return a new Framebuffer Frame Generator;
 */
+ (instancetype)generatorWithScale:(NSDecimalNumber *)scale sink:(id<FBFramebufferFrameSink>)sink queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Properties

/**
 The sink owned by the Frame Generator.
 */
@property (nonatomic, strong, readonly) id<FBFramebufferFrameSink> sink;

#pragma mark Public Methods.

/**
 To be called when there are no further frames.
 */
- (void)frameSteamEndedWithTeardownGroup:(dispatch_group_t)group error:(NSError *)error;

@end

/**
 A Frame Generator for the Xcode 7 'SimDeviceFramebufferBackingStore'
 */
@interface FBFramebufferBackingStoreFrameGenerator : FBFramebufferFrameGenerator

#pragma mark Public Methods

/**
 To be called when the first frame of a Framebuffer Arrives

 @param backingStore the Backing Store that has recieved it's first frame.
 */
- (void)firstFrameWithBackingStore:(SimDeviceFramebufferBackingStore *)backingStore;

/**
 To be called when the backing store of a Framebuffer updates.

 @param backingStore the Backing Store that has been updated.
 */
- (void)backingStoreDidUpdate:(SimDeviceFramebufferBackingStore *)backingStore;

@end

/**
 A Frame Generator for the Xcode 8 'IOSurface'.
 */
@interface FBFramebufferIOSurfaceFrameGenerator : FBFramebufferFrameGenerator

/**
 To be called when the current IOSurface for a Framebuffer changes.

 @param surface the surface that has changed.
 */
- (void)currentSurfaceChanged:(nullable IOSurfaceRef)surface;

@end

NS_ASSUME_NONNULL_END

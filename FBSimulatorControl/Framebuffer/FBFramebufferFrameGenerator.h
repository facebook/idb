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

@protocol FBFramebufferDelegate;
@class FBFramebuffer;
@class SimDeviceFramebufferBackingStore;

NS_ASSUME_NONNULL_BEGIN

/**
 Generates FBFramebufferFrame Objects and forwards them to the delegate.
 */
@interface FBFramebufferFrameGenerator : NSObject <FBJSONSerializable>

#pragma mark Public Intializers

/**
 Creates and returns a new Generator.

 @param framebuffer the Framebuffer to generate frames for.
 @param delegate the Delegate to forward to.
 @param logger the logger to log to.
 @return a new Framebuffer Frame Generator;
 */
+ (instancetype)generatorWithFramebuffer:(FBFramebuffer *)framebuffer delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger;

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

/**
 To be called when there are no further frames.
 */
- (void)frameSteamEnded;

@end

NS_ASSUME_NONNULL_END

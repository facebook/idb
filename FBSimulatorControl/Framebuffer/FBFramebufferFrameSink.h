/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

@class FBFramebuffer;
@class FBFramebufferFrame;

NS_ASSUME_NONNULL_BEGIN

/**
 A Reciever of Generated Frame from a Simulator's Framebuffer.
 */
@protocol FBFramebufferFrameSink <NSObject>

/**
 Called when an Image Frame is available.

 @param frame the updated frame.
 */
- (void)framebuffer:(FBFramebuffer *)framebuffer didUpdate:(FBFramebufferFrame *)frame;

/**
 Called when the framebuffer is no longer valid, typically when the Simulator shuts down.

 @param framebuffer the framebuffer that was updated.
 @param error an error, if any occured in the teardown of the simulator.
 @param teardownGroup a dispatch_group to add asynchronous tasks to that should be performed in the teardown of the Framebuffer.
 */
- (void)framebuffer:(FBFramebuffer *)framebuffer didBecomeInvalidWithError:(NSError *)error teardownGroup:(dispatch_group_t)teardownGroup;

@end

/**
 A Framebuffer Frame Generator that forwards all messages to an array of Frame Generators.
 */
@interface FBFramebufferCompositeFrameSink : NSObject <FBFramebufferFrameSink>

/**
 A Composite Delegate that will notify an array of delegates.

 @param delegates the delegates to call.
 @return a composite framebuffer delegate.
 */
+ (instancetype)withSinks:(NSArray<id<FBFramebufferFrameSink>> *)delegates;

@end

NS_ASSUME_NONNULL_END

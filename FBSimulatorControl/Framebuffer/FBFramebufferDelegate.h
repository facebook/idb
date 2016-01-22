/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulatorFramebuffer;

/**
 A Delegate for Framebuffer related activity.
 */
@protocol FBFramebufferDelegate <NSObject>

/**
 Called when the Size of the Framebuffer becomes available.
 Will be called before frames are sent.

 @param framebuffer the framebuffer that was updated.
 @param size the size of the framebuffer.
 */
- (void)framebuffer:(FBSimulatorFramebuffer *)framebuffer didGetSize:(CGSize)size;

/**
 Called when a new image frame is available.

 @param framebuffer the framebuffer that was updated.
 @param size the size of the image.
 @param image the updated image.
 */
- (void)framebufferDidUpdate:(FBSimulatorFramebuffer *)framebuffer withImage:(CGImageRef)image size:(CGSize)size;

/**
 Called when the framebuffer is no longer valid, typically when the Simulator shuts down.

 @param framebuffer the framebuffer that was updated.
 */
- (void)framebufferDidBecomeInvalid:(FBSimulatorFramebuffer *)framebuffer error:(NSError *)error;

@end

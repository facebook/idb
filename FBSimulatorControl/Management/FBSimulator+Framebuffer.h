/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBSimulator.h>

@class FBFramebuffer;

NS_ASSUME_NONNULL_BEGIN

/**
 Convenience for obtaining a Simulator's Framebuffer.
 */
@interface FBSimulator (Framebuffer)

/**
 Obtains the Framebuffer.

 @param error an error out for any error that occurs.
 @return the Framebuffer on success, nil otherwise.
 */
- (nullable FBFramebuffer *)framebufferWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

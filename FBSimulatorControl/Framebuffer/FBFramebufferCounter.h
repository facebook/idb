/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBFramebufferDelegate.h>

@protocol FBSimulatorLogger;

/**
 A Framebuffer Delegate that counts frames and prints at intervals
 */
@interface FBFramebufferCounter : NSObject <FBFramebufferDelegate>

/**
 Creates a new Framebuffer counter.

 @param logFrequency the frequency with which to log frame counts
 @param logger the logger to log to
 */
+ (instancetype)withLogFrequency:(NSUInteger)logFrequency logger:(id<FBSimulatorLogger>)logger;

/**
 The Frame Count.
 */
@property (atomic, assign, readonly) NSUInteger frameCount;

@end

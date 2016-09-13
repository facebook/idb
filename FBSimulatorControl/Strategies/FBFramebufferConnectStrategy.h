/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBFramebuffer;
@class FBFramebufferConfiguration;
@class FBSimulator;

NS_ASSUME_NONNULL_BEGIN

/**
 A Strategy for Connecting the Framebuffer to a Booted Simulator.
 */
@interface FBFramebufferConnectStrategy : NSObject

/**
 Construct a Strategy for connecting to a Simulator Framebuffer.

 @param configuration the configuration to use
 @return a new Framebuffer Connect Strategy
 */
+ (instancetype)strategyWithConfiguration:(FBFramebufferConfiguration *)configuration;

/**
 Connects the Simulator to the Framebuffer

 @param simulator the simulator to connect to.
 @param error an error out for any error that occurs.
 @return a Framebuffer if successful, NO otherwise.
 */
- (nullable FBFramebuffer *)connect:(FBSimulator *)simulator error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBFramebuffer;
@class FBFramebufferConfiguration;
@class FBSimulator;

/**
 A Strategy for Connecting the Framebuffer to a Booted Simulator.
 */
@interface FBFramebufferConnectStrategy : NSObject

#pragma mark Initializers

/**
 Construct a Strategy for connecting to a Simulator Framebuffer.

 @param configuration the configuration to use
 @return a new Framebuffer Connect Strategy
 */
+ (instancetype)strategyWithConfiguration:(FBFramebufferConfiguration *)configuration;

#pragma mark Connecting

/**
 Connects the Simulator to the Framebuffer

 @param simulator the simulator to connect to.
 @return a Framebuffer if successful, NO otherwise.
 */
- (FBFuture<FBFramebuffer *> *)connect:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END

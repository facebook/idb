/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBSimulator;
@class FBSimulatorBootConfiguration;

/**
 A Strategy for Booting a Simulator's Bridge.
 */
@interface FBSimulatorBootStrategy : NSObject

#pragma mark Properties

/**
 Boots a simulator with the provided configuration.

 @param simulator the simulator to boot.
 @param configuration the configuration to use.
 @return a new FBSimulatorBootStrategy instance.
 */
+ (nonnull FBFuture<NSNull *> *)boot:(nonnull FBSimulator *)simulator withConfiguration:(nonnull FBSimulatorBootConfiguration *)configuration;

@end

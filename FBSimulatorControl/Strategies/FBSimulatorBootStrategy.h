/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;
@class FBSimulatorBootConfiguration;

/**
 A Strategy for Booting a Simulator's Bridge.
 */
@interface FBSimulatorBootStrategy : NSObject

#pragma mark Properties

/**
 Creates and returns a new Strategy strategyWith the given configuration.

 @param configuration the configuration to use.
 @param simulator the simulator to boot.
 @return a new FBSimulatorBootStrategy instance.
 */
+ (instancetype)strategyWithConfiguration:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator;

#pragma mark Public Methods

/**
 Boots the Simulator.

 @return a future that resolves when the Simulator is booted.
 */
- (FBFuture<NSNull *> *)boot;

@end

NS_ASSUME_NONNULL_END

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

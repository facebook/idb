/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcessFetcher;
@class FBSimulator;
@class FBSimulatorSet;
@class SimDevice;

/**
 A Strategy for Creating FBSimulator Instances from SimDevices.
 */
@interface FBSimulatorInflationStrategy : NSObject

/**
 Creates and returns a new Inflation Strategy.

 @param set the Simulator Set to insert into.
 @return a new Simulator Inflation Strategy Instance.
 */
+ (instancetype)strategyForSet:(FBSimulatorSet *)set;

/**
 Creates the Array of Simulators matching the Array of SimDevices passed in.
 Will Create and Remove SimDevice instances so as to make the Simulators and wrapped SimDevices consistent.

 @param simDevices the existing SimDevice Instances.
 @param simulators the existing Simulators (if any).
 @return an array of FBSimulator instances matching the SimDevices.
 */
- (NSArray<FBSimulator *> *)inflateFromDevices:(NSArray<SimDevice *> *)simDevices exitingSimulators:(NSArray<FBSimulator *> *)simulators;

@end

NS_ASSUME_NONNULL_END

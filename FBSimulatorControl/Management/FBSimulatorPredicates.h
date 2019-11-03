/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControl/FBSimulator.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulatorConfiguration;

/**
 Predicates for filtering collections of available Simulators.
 NSCompoundPredicate can be used to compose Predicates.
 All Prediates operate on collections of FBSimulator instances.
 */
@interface FBSimulatorPredicates : FBiOSTargetPredicates

/**
 Predicate for Simulators that are launched.

 @return an NSPredicate.
 */
+ (NSPredicate *)launched;

/**
 Predicate for matching Simulators against a Configuration.

 @param configuration the configuration to match against.
 @return an NSPredicate.
 */
+ (NSPredicate *)configuration:(FBSimulatorConfiguration *)configuration;

/**
 Predicate for matching any of the provided configurations against a Simulator.

 @param configurations the configuration to match against.
 @return an NSPredicate.
 */
+ (NSPredicate *)configurations:(NSArray<FBSimulatorConfiguration *> *)configurations;

@end

NS_ASSUME_NONNULL_END

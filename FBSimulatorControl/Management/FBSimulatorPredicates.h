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

@class FBSimulatorConfiguration;
@class FBSimulatorPool;

/**
 Predicates for filtering collections of available Simulators.
 NSCompoundPredicate can be used to compose Predicates.
 All Prediates operate on FBSimulator instances.
 */
@interface FBSimulatorPredicates : NSObject

#pragma mark Pools

/**
 Predicate for Simulators that are allocated in a specific Pool.

 @param pool the Pool to match against. Must not be nil.
 @return an NSPredicate.
 */
+ (NSPredicate *)allocatedByPool:(FBSimulatorPool *)pool;

/**
 Predicate for Simulators that are managed by a pool but not allocated.

 @param pool the Pool to match against. Must not be nil.
 @return an NSPredicate.
 */
+ (NSPredicate *)unallocatedByPool:(FBSimulatorPool *)pool;

#pragma mark States

/**
 Predicate for Simulators that are launched.

 @return an NSPredicate.
 */
+ (NSPredicate *)launched;

/**
 Predicate for matching against Simulator based on a State.

 @param state the state to match against.
 @return an NSPredicate.
 */
+ (NSPredicate *)state:(FBSimulatorState)state;

/**
 Predicate for matching against a range of Simulator States.

 @param states the states to match against. Must not be nil.
 @return an NSPredicate.
 */
+ (NSPredicate *)states:(NSArray *)states;

#pragma mark Configurations

/**
 Predicate for only the provided Simulator. Useful for negation.

 @param simulator the states to match against. Must not be nil.
 @return an NSPredicate.
 */
+ (NSPredicate *)only:(FBSimulator *)simulator;

/**
 Predicate for matching against a single Simulator UDID.

 @param udid the UDID to match against. Must not be nil.
 @return an NSPredicate.
 */
+ (NSPredicate *)udid:(NSString *)udid;

/**
 Predicate for matching against one of multiple Simulator UDIDs.

 @param udids the UDIDs to match against. Must not be nil.
 @return an NSPredicate.
 */
+ (NSPredicate *)udids:(NSArray *)udids;

/**
 Predicate for matching SimDevices against a Configuration.

 @param configuration the configuration to match against.
 @return an NSPredicate.
 */
+ (NSPredicate *)configuration:(FBSimulatorConfiguration *)configuration;

@end

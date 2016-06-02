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

#import <FBSimulatorControl/FBSimulator.h>

@class FBSimulatorConfiguration;
@class FBSimulatorPool;

@protocol FBControlCoreConfiguration_Device;
@protocol FBControlCoreConfiguration_OS;

NS_ASSUME_NONNULL_BEGIN

/**
 Predicates for filtering collections of available Simulators.
 NSCompoundPredicate can be used to compose Predicates.
 All Prediates operate on collections of FBSimulator instances.
 */
@interface FBSimulatorPredicates : NSObject

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

 @param states An index set of the states to match against.. Must not be nil.
 @return an NSPredicate.
 */
+ (NSPredicate *)states:(NSIndexSet *)states;

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
+ (NSPredicate *)udids:(NSArray<NSString *> *)udids;

/**
 Predicate for matching against one of multiple Simulator Devices.

 @param devices the Device to match against.
 @return an NSPredicate.
 */
+ (NSPredicate *)devices:(NSArray<id<FBControlCoreConfiguration_Device>> *)devices;

/**
 Predicate for matching against one of multiple Simulator Devices.

 @param deviceNames the Device Names to match against
 @return an NSPredicate.
 */
+ (NSPredicate *)devicesNamed:(NSArray<NSString *> *)deviceNames;

/**
 Predicate for matching against one of multiple Simulator OS Versions.

 @param versions the OS Versions to match against.
 @return an NSPredicate.
 */
+ (NSPredicate *)osVersions:(NSArray<id<FBControlCoreConfiguration_OS>> *)versions;

/**
 Predicate for matching against one of multiple Simulator OS Version Names

 @param versionNames the OS Version Names to match against.
 @return an NSPredicate.
 */
+ (NSPredicate *)osVersionsNamed:(NSArray<NSString *> *)versionNames;

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

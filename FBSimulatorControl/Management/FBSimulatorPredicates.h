/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulator;
@class FBSimulatorConfiguration;
@class FBSimulatorPool;

/**
 Predicates for filtering collections of available Simulators.
 NSCompoundPredicate can be used to compose Predicates.
 */
@interface FBSimulatorPredicates : NSObject

/**
 Predicate for Simulators that are allocated in a specific Pool.
 */
+ (NSPredicate *)allocatedByPool:(FBSimulatorPool *)pool;

/**
 Predicate for Simulators that are managed by a pool but not allocated.
 */
+ (NSPredicate *)unallocatedByPool:(FBSimulatorPool *)pool;

/**
 Predicate for Simulators that are launched.
 */
+ (NSPredicate *)launched;

/**
 Predicate for only the provided Simulator.
 */
+ (NSPredicate *)only:(FBSimulator *)simulator;

/**
 Predicate for matching SimDevices against a Configuration.
 */
+ (NSPredicate *)matchingConfiguration:(FBSimulatorConfiguration *)configuration;

@end

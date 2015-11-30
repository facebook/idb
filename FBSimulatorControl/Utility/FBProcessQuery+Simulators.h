/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBProcessQuery.h>

@class FBSimulatorControlConfiguration;

/**
 FBProcessQuery to NSPredicate.
 */
@interface FBProcessQuery (Simulators)

/**
 Fetches an NSArray<id<FBProcessInfo>> of all Simulator Application Processes.
 */
- (NSArray *)simulatorProcesses;

/**
 Returns a Predicate that matches simulator processes only from the Xcode version in the provided configuration.
 
 @param configuration the configuration to match against.
 @return an NSPredicate that operates on an Collection of FBSimulators
 */
+ (NSPredicate *)simulatorsProcessesLaunchedUnderConfiguration:(FBSimulatorControlConfiguration *)configuration;

/**
 Returns a Predicate that matches simulator processes launched by FBSimulatorControl
 
 @return an NSPredicate that operates on an Collection of FBSimulators
 */
+ (NSPredicate *)simulatorProcessesLaunchedBySimulatorControl;

/**
 Constructs a Predicate that matches processes with any of the Simulators in an collection of FBSimulators.
 
 @param simulators an NSArray<FBSimulator *> of the Simulators to match.
 @return an NSPredicate that operates on an Collection of FBSimulators
 */
+ (NSPredicate *)simulatorProcessesMatchingSimulators:(NSArray *)simulators;

/**
 Constructs a Predicate that matches processes with any of the Simulators in an collection String UDIDS.

 @param simulators an NSArray<NSString *> of the Simulator UDIDs to match.
 @return an NSPredicate that operates on an Collection of FBSimulators
 */
+ (NSPredicate *)simulatorProcessesMatchingUDIDs:(NSArray *)simulators;

@end

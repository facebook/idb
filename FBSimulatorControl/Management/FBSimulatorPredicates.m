/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorPredicates.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorPool.h"

@implementation FBSimulatorPredicates

#pragma mark Pools

+ (NSPredicate *)allocatedByPool:(FBSimulatorPool *)pool
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *simulator, NSDictionary *_) {
    return [pool simulatorIsAllocated:simulator];
  }];
}

+ (NSPredicate *)unallocatedByPool:(FBSimulatorPool *)pool
{
  return [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [NSCompoundPredicate notPredicateWithSubpredicate:[self allocatedByPool:pool]],
  ]];
}

+ (NSPredicate *)launched
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *simulator, NSDictionary *_) {
    return simulator.launchdProcess.processIdentifier > 1;
  }];
}

#pragma mark Configurations

+ (NSPredicate *)configuration:(FBSimulatorConfiguration *)configuration
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *candidate, NSDictionary *_) {
    if (![candidate.configuration.device isEqual:configuration.device]) {
      return NO;
    }
    if (![candidate.configuration.os isEqual:configuration.os]) {
      return NO;
    }
    return YES;
  }];
}

+ (NSPredicate *)configurations:(NSArray<FBSimulatorConfiguration *> *)configurations
{
  NSMutableArray<NSPredicate *> *subpredicates = [NSMutableArray array];
  for (FBSimulatorConfiguration *configuration in configurations) {
    [subpredicates addObject:[self configuration:configuration]];
  }
  return [NSCompoundPredicate orPredicateWithSubpredicates:subpredicates];
}

@end

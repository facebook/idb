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

#import "FBSimulator.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorPool+Private.h"
#import "FBSimulatorPool.h"

@implementation FBSimulatorPredicates

+ (NSPredicate *)allocatedByPool:(FBSimulatorPool *)pool
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *simulator, NSDictionary *_) {
    return [pool.allocatedUDIDs containsObject:simulator.udid];
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
    return simulator.processIdentifier > 1 || simulator.launchdSimProcessIdentifier > 1;
  }];
}

+ (NSPredicate *)only:(FBSimulator *)simulator
{
  return [self onlyUDID:simulator.udid];
}

+ (NSPredicate *)onlyUDID:(NSString *)udid
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *candidate, NSDictionary *_) {
    return udid && [candidate.udid isEqual:udid];
  }];
}

+ (NSPredicate *)withState:(FBSimulatorState)state
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *candidate, NSDictionary *_) {
    return candidate.state == state;
  }];
}

+ (NSPredicate *)matchingConfiguration:(FBSimulatorConfiguration *)configuration
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *candidate, NSDictionary *_) {
    return [candidate.device.deviceType.name isEqual:configuration.deviceType.name] &&
           [candidate.device.runtime.name isEqual:configuration.runtime.name];
  }];
}

@end

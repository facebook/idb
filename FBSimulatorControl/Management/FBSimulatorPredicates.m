/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorPredicates.h"

#import "FBSimulator.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorPool+Private.h"

@implementation FBSimulatorPredicates

+ (NSPredicate *)managed
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *simulator, NSDictionary* _) {
    return [simulator isKindOfClass:FBManagedSimulator.class];
  }];
}

+ (NSPredicate *)managedByPool:(FBSimulatorPool *)pool
{
  return [NSCompoundPredicate andPredicateWithSubpredicates:@[
    self.managed,
    [NSPredicate predicateWithBlock:^ BOOL (FBManagedSimulator *simulator, NSDictionary* _) {
      return pool.configuration.bucketID == simulator.bucketID;
    }]
  ]];
}

+ (NSPredicate *)allocatedByPool:(FBSimulatorPool *)pool
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *simulator, NSDictionary* _) {
    return [pool.allocatedUDIDs containsObject:simulator.udid];
  }];
}

+ (NSPredicate *)unallocatedByPool:(FBSimulatorPool *)pool
{
  return [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [self managedByPool:pool],
    [NSCompoundPredicate notPredicateWithSubpredicate:[self allocatedByPool:pool]],
  ]];
}

+ (NSPredicate *)unmanaged
{
  return [NSCompoundPredicate notPredicateWithSubpredicate:self.managed];
}

+ (NSPredicate *)launched
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *simulator, NSDictionary* _) {
    return simulator.processIdentifier > 1 || simulator.launchdSimProcessIdentifier > 1;
  }];
}

+ (NSPredicate *)only:(FBSimulator *)simulator
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *candidate, NSDictionary* _) {
    return simulator.udid && [candidate.udid isEqual:simulator.udid];
  }];
}

@end

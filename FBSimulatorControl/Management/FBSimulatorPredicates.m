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

#pragma mark States

+ (NSPredicate *)launched
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *simulator, NSDictionary *_) {
    return simulator.launchdSimProcess.processIdentifier > 1;
  }];
}

+ (NSPredicate *)state:(FBSimulatorState)state
{
  return [self states:[NSIndexSet indexSetWithIndex:(NSUInteger)state]];
}

+ (NSPredicate *)states:(NSIndexSet *)states
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *candidate, NSDictionary *_) {
    return [states containsIndex:(NSUInteger)candidate.state];
  }];
}

#pragma mark Configurations

+ (NSPredicate *)only:(FBSimulator *)simulator
{
  return [self udid:simulator.udid];
}

+ (NSPredicate *)udid:(NSString *)udid
{
  return [self udids:@[udid]];
}

+ (NSPredicate *)udids:(NSArray<NSString *> *)udids
{
  NSSet<NSString *> *udidsSet = [NSSet setWithArray:udids];

  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *candidate, NSDictionary *_) {
    return [udidsSet containsObject:candidate.udid];
  }];
}

+ (NSPredicate *)devices:(NSArray<id<FBControlCoreConfiguration_Device>> *)devices
{
  return [self devicesNamed:[devices valueForKey:@"deviceName"]];
}

+ (NSPredicate *)devicesNamed:(NSArray<NSString *> *)deviceNames
{
  NSSet<NSString *> *nameSet = [NSSet setWithArray:deviceNames];

  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *candidate, NSDictionary *_) {
    return [nameSet containsObject:candidate.device.name];
  }];
}

+ (NSPredicate *)osVersions:(NSArray<id<FBControlCoreConfiguration_OS>> *)versions;
{
  return [self osVersionsNamed:[versions valueForKey:@"name"]];
}

+ (NSPredicate *)osVersionsNamed:(NSArray<NSString *> *)versionNames
{
  NSSet<NSString *> *nameSet = [NSSet setWithArray:versionNames];

  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *candidate, NSDictionary *_) {
    return [nameSet containsObject:candidate.device.runtime.name];
  }];
}

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

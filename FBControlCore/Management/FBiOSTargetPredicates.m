/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBiOSTargetPredicates.h"

@implementation FBiOSTargetPredicates

+ (NSPredicate *)only:(id<FBiOSTarget>)target
{
  return [self udid:target.udid];
}

+ (NSPredicate *)state:(FBSimulatorState)state
{
  return [self states:[NSIndexSet indexSetWithIndex:(NSUInteger)state]];
}

+ (NSPredicate *)states:(NSIndexSet *)states
{
  return [NSPredicate predicateWithBlock:^ BOOL (id<FBiOSTarget> candidate, NSDictionary *_) {
    return [states containsIndex:(NSUInteger)candidate.state];
  }];
}

+ (NSPredicate *)targetType:(FBiOSTargetType)targetType
{
  return [NSPredicate predicateWithBlock:^ BOOL (id<FBiOSTarget> candidate, NSDictionary *_) {
    return (candidate.targetType & targetType) != FBiOSTargetTypeNone;
  }];
}

+ (NSPredicate *)udid:(NSString *)udid
{
  return [self udids:@[udid]];
}

+ (NSPredicate *)udids:(NSArray<NSString *> *)udids
{
  NSSet<NSString *> *udidsSet = [NSSet setWithArray:udids];

  return [NSPredicate predicateWithBlock:^ BOOL (id<FBiOSTarget> candidate, NSDictionary *_) {
    return [udidsSet containsObject:candidate.udid];
  }];
}

+ (NSPredicate *)devices:(NSArray<id<FBControlCoreConfiguration_Device>> *)deviceConfigurations
{
  NSSet<id<FBControlCoreConfiguration_Device>> *deviceConfigurationSet = [NSSet setWithArray:deviceConfigurations];

  return [NSPredicate predicateWithBlock:^ BOOL (id<FBiOSTarget> candidate, NSDictionary *_) {
    return [deviceConfigurationSet containsObject:candidate.deviceConfiguration];
  }];
}

+ (NSPredicate *)osVersions:(NSArray<id<FBControlCoreConfiguration_OS>> *)osVersions
{
  NSSet<id<FBControlCoreConfiguration_OS>> *osConfigurationSet = [NSSet setWithArray:osVersions];

  return [NSPredicate predicateWithBlock:^ BOOL (id<FBiOSTarget> candidate, NSDictionary *_) {
    return [osConfigurationSet containsObject:candidate.osConfiguration];
  }];
}

@end

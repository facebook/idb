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

+ (NSPredicate *)architectures:(NSArray<NSString *> *)architectures
{
  NSSet<NSString *> *architecturesSet = [NSSet setWithArray:architectures];

  return [NSPredicate predicateWithBlock:^ BOOL (id<FBiOSTarget> candidate, NSDictionary *_) {
    return [architecturesSet containsObject:candidate.architecture];
  }];
}

+ (NSPredicate *)targetType:(FBiOSTargetType)targetType
{
  return [NSPredicate predicateWithBlock:^ BOOL (id<FBiOSTarget> candidate, NSDictionary *_) {
    return (candidate.targetType & targetType) != FBiOSTargetTypeNone;
  }];
}

+ (NSPredicate *)names:(NSArray<NSString *> *)names
{
  NSSet<NSString *> *namesSet = [NSSet setWithArray:names];

  return [NSPredicate predicateWithBlock:^ BOOL (id<FBiOSTarget> candidate, NSDictionary *_) {
    return [namesSet containsObject:candidate.name];
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

+ (NSPredicate *)devices:(NSArray<FBDeviceModel> *)deviceConfigurations
{
  NSSet<FBDeviceModel> *deviceConfigurationSet = [NSSet setWithArray:deviceConfigurations];

  return [NSPredicate predicateWithBlock:^ BOOL (id<FBiOSTarget> candidate, NSDictionary *_) {
    return [deviceConfigurationSet containsObject:candidate.deviceType.model];
  }];
}

+ (NSPredicate *)osVersions:(NSArray<FBOSVersionName> *)osVersions
{
  NSSet<FBOSVersionName> *osConfigurationSet = [NSSet setWithArray:osVersions];

  return [NSPredicate predicateWithBlock:^ BOOL (id<FBiOSTarget> candidate, NSDictionary *_) {
    return [osConfigurationSet containsObject:candidate.osVersion.name];
  }];
}

@end

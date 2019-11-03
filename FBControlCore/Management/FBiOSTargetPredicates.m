/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetPredicates.h"

@implementation FBiOSTargetPredicates

+ (NSPredicate *)only:(id<FBiOSTarget>)target
{
  return [self udid:target.udid];
}

+ (NSPredicate *)state:(FBiOSTargetState)state
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

+ (NSPredicate *)udidsOfType:(FBiOSTargetType)targetType
{
  NSMutableString *format = [@"FALSEPREDICATE" mutableCopy];
  if (targetType & FBiOSTargetTypeDevice) {
    [format appendString:@" OR SELF MATCHES '^[[:xdigit:]]{40}$' OR SELF MATCHES '0000[[:xdigit:]]{4}-00[[:xdigit:]]*$'"];
  }
  if (targetType & FBiOSTargetTypeSimulator) {
    [format appendString:@" OR SELF MATCHES '^[[:xdigit:]]{8}-([[:xdigit:]]{4}-){3}[[:xdigit:]]{12}$'"];
  }
  if (targetType & FBiOSTargetTypeLocalMac) {
    [format appendString:@" OR SELF MATCHES '^[[:alnum:]]{12}$'"];
  }
  return [NSPredicate predicateWithFormat:format];
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

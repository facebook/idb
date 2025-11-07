/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTarget.h"

#import "FBiOSTargetConfiguration.h"
NSString *FBiOSTargetStateStringFromState(FBiOSTargetState state)
{
  switch (state) {
    case FBiOSTargetStateCreating:
      return FBiOSTargetStateStringCreating;
    case FBiOSTargetStateShutdown:
      return FBiOSTargetStateStringShutdown;
    case FBiOSTargetStateBooting:
      return FBiOSTargetStateStringBooting;
    case FBiOSTargetStateBooted:
      return FBiOSTargetStateStringBooted;
    case FBiOSTargetStateShuttingDown:
      return FBiOSTargetStateStringShuttingDown;
    case FBiOSTargetStateDFU:
      return FBiOSTargetStateStringDFU;
    case FBiOSTargetStateRecovery:
      return FBiOSTargetStateStringRecovery;
    case FBiOSTargetStateRestoreOS:
      return FBiOSTargetStateStringRestoreOS;
    case FBiOSTargetStateUnknown:
    default:
      return FBiOSTargetStateStringUnknown;
  }
}

FBiOSTargetState FBiOSTargetStateFromStateString(NSString *stateString)
{
  stateString = [stateString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@" "];
  if ([stateString isEqualToString:FBiOSTargetStateStringCreating.lowercaseString]) {
    return FBiOSTargetStateCreating;
  }
  if ([stateString isEqualToString:FBiOSTargetStateStringShutdown.lowercaseString]) {
    return FBiOSTargetStateShutdown;
  }
  if ([stateString isEqualToString:FBiOSTargetStateStringBooting.lowercaseString]) {
    return FBiOSTargetStateBooting;
  }
  if ([stateString isEqualToString:FBiOSTargetStateStringBooted.lowercaseString]) {
    return FBiOSTargetStateBooted;
  }
  if ([stateString isEqualToString:FBiOSTargetStateStringShuttingDown.lowercaseString]) {
    return FBiOSTargetStateShuttingDown;
  }
  if ([stateString isEqualToString:FBiOSTargetStateStringDFU.lowercaseString]) {
    return FBiOSTargetStateDFU;
  }
  if ([stateString isEqualToString:FBiOSTargetStateStringRecovery.lowercaseString]) {
    return FBiOSTargetStateRecovery;
  }
  if ([stateString isEqualToString:FBiOSTargetStateStringRestoreOS.lowercaseString]) {
    return FBiOSTargetStateRestoreOS;
  }
  return FBiOSTargetStateUnknown;
}

NSString *FBiOSTargetTypeStringFromTargetType(FBiOSTargetType targetType)
{
  if (targetType == FBiOSTargetTypeDevice) {
    return @"Device";
  }
  if (targetType == FBiOSTargetTypeSimulator) {
    return @"Simulator";
  }
  if (targetType == FBiOSTargetTypeLocalMac) {
    return @"Mac";
  }
  return @"Unknown";
}

NSComparisonResult FBiOSTargetComparison(id<FBiOSTarget> left, id<FBiOSTarget> right)
{
  NSComparisonResult comparison = [@(left.targetType) compare:@(right.targetType)];
  if (comparison != NSOrderedSame) {
    return comparison;
  }
  comparison = [left.osVersion.number compare:right.osVersion.number];
  if (comparison != NSOrderedSame) {
    return comparison;
  }
  comparison = [@(left.deviceType.family) compare:@(right.deviceType.family)];
  if (comparison != NSOrderedSame) {
    return comparison;
  }
  comparison = [left.deviceType.model compare:right.deviceType.model];
  if (comparison != NSOrderedSame) {
    return comparison;
  }
  comparison = [@(left.state) compare:@(right.state)];
  if (comparison != NSOrderedSame) {
    return comparison;
  }
  return [left.udid compare:right.udid];
}

NSString *FBiOSTargetDescribe(id<FBiOSTargetInfo> target)
{
  return [NSString stringWithFormat:
    @"%@ | %@ | %@ | %@ | %@ ",
    target.udid,
    target.name,
    FBiOSTargetStateStringFromState(target.state),
    target.deviceType.model,
    target.osVersion
  ];
}


NSPredicate *FBiOSTargetPredicateForUDID(NSString *udid)
{
  return FBiOSTargetPredicateForUDIDs(@[udid]);
}

NSPredicate *FBiOSTargetPredicateForUDIDs(NSArray<NSString *> *udids)
{
  NSSet<NSString *> *udidsSet = [NSSet setWithArray:udids];

  return [NSPredicate predicateWithBlock:^ BOOL (id<FBiOSTarget> candidate, NSDictionary *_) {
    return [udidsSet containsObject:candidate.udid];
  }];
}

FBFuture<NSNull *> *FBiOSTargetResolveState(id<FBiOSTarget> target, FBiOSTargetState state)
{
  return [FBFuture onQueue:target.workQueue resolveWhen:^ BOOL {
    return target.state == state;
  }];
}

FBFuture<NSNull *> *FBiOSTargetResolveLeavesState(id<FBiOSTarget> target, FBiOSTargetState state)
{
  return [FBFuture onQueue:target.workQueue resolveWhen:^ BOOL {
    return target.state != state;
  }];
}

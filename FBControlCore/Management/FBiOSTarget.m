/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBiOSTarget.h"

#import "FBControlCoreConfigurationVariants.h"

NSString *FBSimulatorStateStringFromState(FBSimulatorState state)
{
  switch (state) {
    case FBSimulatorStateCreating:
      return @"Creating";
    case FBSimulatorStateShutdown:
      return @"Shutdown";
    case FBSimulatorStateBooting:
      return @"Booting";
    case FBSimulatorStateBooted:
      return @"Booted";
    case FBSimulatorStateShuttingDown:
      return @"Shutting Down";
    default:
      return @"Unknown";
  }
}

FBSimulatorState FBSimulatorStateFromStateString(NSString *stateString)
{
  stateString = [stateString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@" "];
  if ([stateString isEqualToString:@"creating"]) {
    return FBSimulatorStateCreating;
  }
  if ([stateString isEqualToString:@"shutdown"]) {
    return FBSimulatorStateShutdown;
  }
  if ([stateString isEqualToString:@"booting"]) {
    return FBSimulatorStateBooting;
  }
  if ([stateString isEqualToString:@"booted"]) {
    return FBSimulatorStateBooted;
  }
  if ([stateString isEqualToString:@"creating"]) {
    return FBSimulatorStateCreating;
  }
  if ([stateString isEqualToString:@"shutting down"]) {
    return FBSimulatorStateShuttingDown;
  }
  return FBSimulatorStateUnknown;
}

NSArray<NSString *> *FBiOSTargetTypeStringsFromTargetType(FBiOSTargetType targetType)
{
  NSMutableArray<NSString *> *strings = [NSMutableArray array];
  if ((targetType & FBiOSTargetTypeDevice) == FBiOSTargetTypeDevice) {
    [strings addObject:@"Device"];
  }
  if ((targetType & FBiOSTargetTypeSimulator) == FBiOSTargetTypeSimulator) {
    [strings addObject:@"Simulator"];
  }
  return [strings copy];
}

extern FBiOSTargetType FBiOSTargetTypeFromTargetTypeStrings(NSArray<NSString *> *targetTypeStrings)
{
  FBiOSTargetType targetType = FBiOSTargetTypeNone;
  for (NSString *string in targetTypeStrings) {
    NSString *targetTypeString = [string.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@" "];
    if ([targetTypeString isEqualToString:@"simulator"]) {
      targetType = targetType | FBiOSTargetTypeSimulator;
    }
    if ([targetTypeString isEqualToString:@"device"]) {
      targetType = targetType | FBiOSTargetTypeDevice;
    }
  }

  return targetType;
}

extern NSComparisonResult FBiOSTargetComparison(id<FBiOSTarget> left, id<FBiOSTarget> right)
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

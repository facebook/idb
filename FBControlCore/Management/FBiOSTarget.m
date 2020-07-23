/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTarget.h"

#import "FBiOSTargetConfiguration.h"

FBiOSTargetStateString const FBiOSTargetStateStringCreating = @"Creating";
FBiOSTargetStateString const FBiOSTargetStateStringShutdown = @"Shutdown";
FBiOSTargetStateString const FBiOSTargetStateStringBooting = @"Booting";
FBiOSTargetStateString const FBiOSTargetStateStringBooted = @"Booted";
FBiOSTargetStateString const FBiOSTargetStateStringShuttingDown = @"Shutting Down";
FBiOSTargetStateString const FBiOSTargetStateStringDFU = @"DFU";
FBiOSTargetStateString const FBiOSTargetStateStringRecovery = @"Recovery";
FBiOSTargetStateString const FBiOSTargetStateStringRestoreOS = @"RestoreOS";
FBiOSTargetStateString const FBiOSTargetStateStringUnknown = @"Unknown";


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

NSArray<NSString *> *FBiOSTargetTypeStringsFromTargetType(FBiOSTargetType targetType)
{
  NSMutableArray<NSString *> *strings = [NSMutableArray array];
  if ((targetType & FBiOSTargetTypeDevice) == FBiOSTargetTypeDevice) {
    [strings addObject:@"Device"];
  }
  if ((targetType & FBiOSTargetTypeSimulator) == FBiOSTargetTypeSimulator) {
    [strings addObject:@"Simulator"];
  }
  if ((targetType & FBiOSTargetTypeLocalMac) == FBiOSTargetTypeLocalMac) {
    [strings addObject:@"Mac"];
  }
  return [strings copy];
}

FBiOSTargetType FBiOSTargetTypeFromTargetTypeStrings(NSArray<NSString *> *targetTypeStrings)
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
    if ([targetTypeString isEqualToString:@"mac"]) {
      targetType = targetType | FBiOSTargetTypeLocalMac;
    }
  }

  return targetType;
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

NSString *FBiOSTargetDefaultScreenshotPath(NSString *storageDirectory)
{
  return [storageDirectory stringByAppendingPathComponent:@"video.mp4"];
}

NSString *FBiOSTargetDefaultVideoPath(NSString *storageDirectory)
{
  return [storageDirectory stringByAppendingPathComponent:@"screenshot.png"];
}

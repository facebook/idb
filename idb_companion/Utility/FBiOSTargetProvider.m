/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetProvider.h"

#import <FBDeviceControl/FBDeviceControl.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBIDBError.h"

@implementation FBiOSTargetProvider

+ (FBiOSTargetType)targetTypeForUDID:(NSString *)udid
{
  const FBiOSTargetType types[3] = {FBiOSTargetTypeDevice, FBiOSTargetTypeSimulator, FBiOSTargetTypeLocalMac};
  for (NSUInteger idx = 0; idx < 3; idx++) {
    FBiOSTargetType type = types[idx];
    NSPredicate *devicePredicate = [FBiOSTargetPredicates udidsOfType:type];
    if ([devicePredicate evaluateWithObject:udid]) {
      return type;
    }
  }
  return FBiOSTargetTypeNone;
}

#pragma mark Public

+ (FBFuture<id<FBiOSTarget>> *)targetWithUDID:(NSString *)udid targetSets:(NSArray<id<FBiOSTargetSet>> *)targetSets warmUp:(BOOL)warmUp logger:(id<FBControlCoreLogger>)logger
{
  NSError *error = nil;
  if ([udid.lowercaseString isEqualToString:@"only"]) {
    id<FBiOSTarget> target = [self fetchSoleTargetForTargetSets:targetSets logger:logger error:&error];
    if (!target) {
      return [FBFuture futureWithError:error];
    }
    return [FBFuture futureWithResult:target];
  }
  id<FBiOSTarget> target = [self fetchTargetWithUDID:udid targetSets:targetSets logger:logger error:&error];
  if (!target) {
    return [FBFuture futureWithError:error];
  }
  if (!warmUp) {
    return [FBFuture futureWithResult:target];
  }
  if (target.state != FBiOSTargetStateBooted) {
    return [FBFuture futureWithResult:target];
  }
  id<FBSimulatorLifecycleCommands> lifecycle = (id<FBSimulatorLifecycleCommands>) target;
  if (![lifecycle conformsToProtocol:@protocol(FBSimulatorLifecycleCommands)]) {
    return [FBFuture futureWithResult:target];;
  }
  return [[lifecycle
    connectToBridge]
    mapReplace:target];
}

#pragma mark Private

+ (id<FBiOSTarget>)fetchTargetWithUDID:(NSString *)udid targetSets:(NSArray<id<FBiOSTargetSet>> *)targetSets logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  // Obtain the Target Type for the input UDID
  FBiOSTargetType targetType = [self targetTypeForUDID:udid];
  if (targetType == FBiOSTargetTypeNone) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not valid UDID", udid]
      fail:error];
  }
  // Get a mac device if one was requested
  if (targetType == FBiOSTargetTypeLocalMac) {
    FBMacDevice *mac = [[FBMacDevice alloc] initWithLogger:logger];
    if (![mac.udid isEqual:udid]) {
      return nil;
    }
    return mac;
  }
  // Otherwise query the input target sets
  FBiOSTargetQuery *query = [FBiOSTargetQuery udid:udid];
  for (id<FBiOSTargetSet> targetSet in targetSets) {
    id<FBiOSTargetInfo> targetInfo = [[query filter:targetSet.allTargetInfos] firstObject];
    if (!targetInfo) {
      continue;
    }
    if (![targetInfo conformsToProtocol:@protocol(FBiOSTarget)]) {
      return [[FBDeviceControlError
        describeFormat:@"UDID %@ exists, but the target is not usable %@", udid, targetInfo]
        fail:error];
    }
    return (id<FBiOSTarget>) targetInfo;
  }

  return [[FBIDBError
    describeFormat:@"%@ could not be resolved to any target in %@", udid, targetSets]
    fail:error];
}

+ (id<FBiOSTarget>)fetchSoleTargetForTargetSets:(NSArray<id<FBiOSTargetSet>> *)targetSets logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSMutableArray<id<FBiOSTarget>> *targets = NSMutableArray.array;
  for (id<FBiOSTargetSet> targetSet in targetSets) {
    [targets addObjectsFromArray:(NSArray<id<FBiOSTarget>> *)targetSet.allTargetInfos];
  }
  if (targets.count > 1) {
    return [[FBIDBError
      describeFormat:@"Cannot get a sole target when multiple found %@", [FBCollectionInformation oneLineDescriptionFromArray:targets]]
      fail:error];
  }
  if (targets.count == 0) {
    return [[FBIDBError
      describeFormat:@"Cannot get a sole target when none were found in target sets %@", [FBCollectionInformation oneLineDescriptionFromArray:targetSets]]
      fail:error];
  }
  return targets.firstObject;
}

@end

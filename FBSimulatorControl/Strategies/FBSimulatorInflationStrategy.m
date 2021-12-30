/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorInflationStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorSet.h"

@interface FBSimulatorInflationStrategy ()

@property (nonatomic, weak, readonly) FBSimulatorSet *set;

@end

@implementation FBSimulatorInflationStrategy

+ (instancetype)strategyForSet:(FBSimulatorSet *)set
{
  return [[self alloc] initWithSet:set];
}

- (instancetype)initWithSet:(FBSimulatorSet *)set
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;

  return self;
}

- (NSArray<FBSimulator *> *)inflateFromDevices:(NSArray<SimDevice *> *)simDevices exitingSimulators:(NSArray<FBSimulator *> *)simulators
{
  // Inflate new simulators that have come along since last time this method was called.
  NSSet<NSString *> *existingSimulatorUDIDs = [NSSet setWithArray:[simulators valueForKeyPath:@"udid"]];
  NSDictionary<NSString *, SimDevice *> *availableDevices = [NSDictionary
    dictionaryWithObjects:simDevices
    forKeys:[simDevices valueForKeyPath:@"UDID.UUIDString"]];

  // Calculate the new Devices that are available.
  NSMutableSet<NSString *> *simulatorsToInflate = [NSMutableSet setWithArray:availableDevices.allKeys];
  [simulatorsToInflate minusSet:existingSimulatorUDIDs];

  // Calculate the Devices that are now gone.
  NSMutableSet<NSString *> *simulatorsToCull = [existingSimulatorUDIDs mutableCopy];
  [simulatorsToCull minusSet:[NSSet setWithArray:availableDevices.allKeys]];

  // The hottest path, so return early to avoid doing any other work.
  if (simulatorsToInflate.count == 0 && simulatorsToCull == 0) {
    return simulators;
  }

  // Cull Simulators
  if (simulatorsToCull.count > 0) {
    NSPredicate *predicate = [NSCompoundPredicate notPredicateWithSubpredicate:FBiOSTargetPredicateForUDIDs(simulatorsToCull.allObjects)];
    simulators = [simulators filteredArrayUsingPredicate:predicate];
  }

  // Inflate the Simulators and join the array.
  NSArray<FBSimulator *> *inflatedSimulators = [self inflateSimulators:simulatorsToInflate.allObjects availableDevices:availableDevices];
  return [simulators arrayByAddingObjectsFromArray:inflatedSimulators];
}

#pragma mark Private

- (NSArray<FBSimulator *> *)inflateSimulators:(NSArray<NSString *> *)simulatorsToInflate availableDevices:(NSDictionary<NSString *, SimDevice *> *)availableDevices
{
  NSMutableArray<FBSimulator *> *inflatedSimulators = [NSMutableArray array];
  for (NSString *udid in simulatorsToInflate) {
    SimDevice *device = availableDevices[udid];
    FBSimulator *simulator = [FBSimulator
      fromSimDevice:device
      configuration:nil
      set:self.set];
    [inflatedSimulators addObject:simulator];
  }
  return [inflatedSimulators copy];
}

@end

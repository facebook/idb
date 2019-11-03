/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorInflationStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorSet.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBSimulatorInflationStrategy ()

@property (nonatomic, weak, readonly) FBSimulatorSet *set;
@property (nonatomic, strong, readonly) FBSimulatorProcessFetcher *processFetcher;

@end

@implementation FBSimulatorInflationStrategy

+ (instancetype)strategyForSet:(FBSimulatorSet *)set
{
  return [[self alloc] initWithSet:set processFetcher:set.processFetcher];
}

- (instancetype)initWithSet:(FBSimulatorSet *)set processFetcher:(FBSimulatorProcessFetcher *)processFetcher
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;
  _processFetcher = processFetcher;

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
    NSPredicate *predicate = [NSCompoundPredicate notPredicateWithSubpredicate:[FBiOSTargetPredicates udids:simulatorsToCull.allObjects]];
    simulators = [simulators filteredArrayUsingPredicate:predicate];
  }

  // Inflate the Simulators and join the array.
  NSArray<FBProcessInfo *> *previouslyIdentifiedContainerApplications = [[simulators valueForKey:@"containerApplication"] filteredArrayUsingPredicate:NSPredicate.notNullPredicate];
  NSArray<FBSimulator *> *inflatedSimulators = [self
    inflateSimulators:simulatorsToInflate.allObjects
    availableDevices:availableDevices
    previouslyIdentifiedContainerApplications:previouslyIdentifiedContainerApplications];
  return [simulators arrayByAddingObjectsFromArray:inflatedSimulators];
}

#pragma mark Private

- (NSArray<FBSimulator *> *)inflateSimulators:(NSArray<NSString *> *)simulatorsToInflate availableDevices:(NSDictionary<NSString *, SimDevice *> *)availableDevices previouslyIdentifiedContainerApplications:(NSArray<FBProcessInfo *> *)previouslyIdentifiedContainerApplications
{
  NSArray<FBProcessInfo *> *unclaimedContainerApplications = nil;
  NSDictionary<NSString *, FBProcessInfo *> *launchdSims = [self.processFetcher launchdProcessesByUDIDs:simulatorsToInflate];
  NSDictionary<NSString *, FBProcessInfo *> *containerApplications = [self.processFetcher simulatorApplicationProcessesByUDIDs:simulatorsToInflate unclaimed:&unclaimedContainerApplications];

  containerApplications = [FBSimulatorInflationStrategy
    adjustContainerApplicationsMapping:containerApplications
    forLaunchdSims:launchdSims
    withUnclaimedContainerApplications:unclaimedContainerApplications
    previouslyIdentifiedContainerApplications:previouslyIdentifiedContainerApplications];

  NSMutableArray<FBSimulator *> *inflatedSimulators = [NSMutableArray array];
  for (NSString *udid in simulatorsToInflate) {
    SimDevice *device = availableDevices[udid];
    FBSimulator *simulator = [FBSimulator
      fromSimDevice:device
      configuration:nil
      launchdSimProcess:launchdSims[udid]
      containerApplicationProcess:containerApplications[udid]
      set:self.set];
    [inflatedSimulators addObject:simulator];
  }
  return [inflatedSimulators copy];
}

+ (NSDictionary<NSString *, FBProcessInfo *> *)adjustContainerApplicationsMapping:(NSDictionary<NSString *, FBProcessInfo *> *)containerApplications forLaunchdSims:(NSDictionary<NSString *, FBProcessInfo *> *)launchdSims withUnclaimedContainerApplications:(NSArray<FBProcessInfo *> *)unclaimedContainerApplications previouslyIdentifiedContainerApplications:(NSArray<FBProcessInfo *> *)previouslyIdentifiedContainerApplications
{
  // We can only correlate when we have one unclaimed Simulator Application.
  if (unclaimedContainerApplications.count != 1) {
    return containerApplications;
  }
  // Confirm that this one remaining container application hasn't been previously correlated with another Simulator.
  NSMutableSet<FBProcessInfo *> *remainingUnclaimed = [NSMutableSet setWithArray:unclaimedContainerApplications];
  [remainingUnclaimed minusSet:[NSSet setWithArray:previouslyIdentifiedContainerApplications]];
  if (remainingUnclaimed.count != 1) {
    return containerApplications;
  }

  // Check the Simulators that are unclaimed, if there are none there's nothing to correlate.
  NSMutableSet<NSString *> *unclaimedSimulatorUDIDs = [NSMutableSet setWithArray:launchdSims.allKeys];
  [unclaimedSimulatorUDIDs minusSet:[NSSet setWithArray:containerApplications.allKeys]];
  if (unclaimedSimulatorUDIDs.count != 1) {
    return containerApplications;
  }

  // Assume that this sole unclaimed Simulator App belongs to the 'Containerless' Booted UDID.
  NSString *untaggedAssumedUDID = [unclaimedSimulatorUDIDs anyObject];
  NSMutableDictionary *adjustedContainerApplications = [containerApplications mutableCopy];
  adjustedContainerApplications[untaggedAssumedUDID] = [unclaimedContainerApplications firstObject];
  return [adjustedContainerApplications copy];
}

@end

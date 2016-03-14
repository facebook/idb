/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorHistory+Queries.h"

#import "FBProcessLaunchConfiguration.h"
#import "FBSimulatorApplication.h"

@interface FBProcessLaunchConfiguration (HistoryQueries)

- (FBSimulatorBinary *)binary;

@end

@implementation FBProcessLaunchConfiguration (HistoryQueries)

- (FBSimulatorBinary *)binary
{
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

@end

@implementation FBSimulatorHistory (Queries)

- (NSArray *)launchedApplicationProcesses
{
  return [self.launchedProcesses filteredArrayUsingPredicate:self.predicateForUserLaunchedApplicationProcesses];
}

- (NSArray *)launchedAgentProcesses
{
  return [self.launchedProcesses filteredArrayUsingPredicate:self.predicateForUserLaunchedAgentProcesses];
}

- (NSArray *)allUserLaunchedProcesses
{
  NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSet];
  FBSimulatorHistory *history = self;
  while (history) {
    [set addObjectsFromArray:history.launchedProcesses];
    history = history.previousState;
  }
  return [set array];
}

- (NSArray<FBProcessInfo *> *)allLaunchedApplicationProcesses
{
  return [self.allUserLaunchedProcesses filteredArrayUsingPredicate:self.predicateForUserLaunchedApplicationProcesses];
}

- (NSArray<FBProcessInfo *> *)allLaunchedAgentProcesses
{
  return [self.allUserLaunchedProcesses filteredArrayUsingPredicate:self.predicateForUserLaunchedAgentProcesses];
}

- (NSArray<FBProcessLaunchConfiguration *> *)allProcessLaunches
{
  return [self.processLaunchConfigurations objectsForKeys:self.launchedProcesses notFoundMarker:NSNull.null];
}

- (NSArray<FBApplicationLaunchConfiguration *> *)allApplicationLaunches
{
  return (NSArray<FBApplicationLaunchConfiguration *> *) [self.allProcessLaunches filteredArrayUsingPredicate:[FBSimulatorHistory predicateForApplicationLaunches]];
}

- (NSArray<FBAgentLaunchConfiguration *> *)allAgentLaunches
{
  return (NSArray<FBAgentLaunchConfiguration *> *) [self.allProcessLaunches
    filteredArrayUsingPredicate:[NSCompoundPredicate notPredicateWithSubpredicate:[FBSimulatorHistory predicateForApplicationLaunches]]
  ];
}

- (FBProcessInfo *)lastLaunchedApplicationProcess
{
  // launchedProcesses has last event based ordering. Message-to-nil will return immediately in base-case.
  return self.launchedApplicationProcesses.firstObject ?: self.previousState.lastLaunchedApplicationProcess;
}

- (FBProcessInfo *)lastLaunchedAgentProcess
{
  // launchedProcesses has last event based ordering. Message-to-nil will return immediately in base-case.
  return self.launchedAgentProcesses.firstObject ?: self.previousState.lastLaunchedAgentProcess;
}

- (FBApplicationLaunchConfiguration *)lastLaunchedApplication
{
  return self.processLaunchConfigurations[self.lastLaunchedApplicationProcess];
}

- (FBAgentLaunchConfiguration *)lastLaunchedAgent
{
  return self.processLaunchConfigurations[self.lastLaunchedAgentProcess];
}

- (FBProcessInfo *)runningProcessForLaunchConfiguration:(FBProcessLaunchConfiguration *)launchConfig
{
  return [self runningProcessForBinary:launchConfig.binary];
}

- (FBProcessInfo *)runningProcessForBinary:(FBSimulatorBinary *)binary
{
  return [[self.launchedApplicationProcesses
    filteredArrayUsingPredicate:[FBSimulatorHistory predicateForBinary:binary]]
    firstObject];
}

- (FBProcessInfo *)runningProcessForApplication:(FBSimulatorApplication *)application
{
  return [self runningProcessForApplication:application recursive:NO];
}

- (NSDictionary<FBProcessInfo *, NSNumber *> *)processTerminationStatuses
{
  NSDictionary *processMetadata = self.processMetadata;
  NSMutableDictionary *statuses = [NSMutableDictionary dictionary];
  for (FBProcessInfo *process in processMetadata) {
    NSDictionary *diagnostics = processMetadata[process];
    NSNumber *terminationStatus = diagnostics[FBSimulatorHistoryDiagnosticNameTerminationStatus];
    if (![terminationStatus isKindOfClass:NSNumber.class]) {
      continue;
    }
    statuses[process] = terminationStatus;
  }
  return [statuses copy];
}

- (instancetype)lastChangeOfState:(FBSimulatorState)state
{
  for (FBSimulatorHistory *history in [self changesToSimulatorState]) {
    if (history.simulatorState == state) {
      return history;
    }
  }
  return nil;
}

- (NSArray<FBSimulatorHistory *> *)changesToSimulatorState
{
  return [self changesToKeyPath:@"simulatorState"];
}

- (NSDate *)startDate
{
  return self.firstHistoryItem.timestamp;
}

#pragma mark - Private

- (NSArray *)changesToKeyPath:(NSString *)keyPath
{
  FBSimulatorHistory *history = self;
  id value = [history valueForKeyPath:keyPath];
  NSMutableArray *array = [NSMutableArray array];
  [array addObject:history];

  while (history) {
    id nextValue = [history valueForKeyPath:keyPath];
    if (![value isEqual:nextValue]) {
      [array addObject:history];
    }
    value = nextValue;
    history = history.previousState;
  }

  return [array copy];
}

- (FBProcessInfo *)runningProcessForApplication:(FBSimulatorApplication *)application recursive:(BOOL)recursive
{
  FBProcessInfo *process = [self runningProcessForBinary:application.binary];
  if (process) {
    return process;
  }

  return recursive ? [self.previousState runningProcessForApplication:application recursive:recursive] : nil;
}

- (instancetype)firstHistoryItem
{
  if (self.previousState == nil) {
    return self;
  }
  return self.previousState.firstHistoryItem;
}

#pragma mark Predicates

+ (NSPredicate *)predicateForBinary:(FBSimulatorBinary *)binary
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
    return [process.launchPath isEqualToString:binary.path];
  }];
}

+ (NSPredicate *)predicateForApplicationLaunches
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessLaunchConfiguration *processLaunch, NSDictionary *_) {
    return [processLaunch isKindOfClass:FBApplicationLaunchConfiguration.class];
  }];
}

- (NSPredicate *)predicateForUserLaunchedApplicationProcesses
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
    return [self.processLaunchConfigurations[process] isKindOfClass:FBApplicationLaunchConfiguration.class];
  }];
}

- (NSPredicate *)predicateForUserLaunchedAgentProcesses
{
  return [NSCompoundPredicate notPredicateWithSubpredicate:
    [self predicateForUserLaunchedApplicationProcesses]
  ];
}

@end

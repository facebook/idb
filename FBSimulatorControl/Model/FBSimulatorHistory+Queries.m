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

@interface FBProcessLaunchConfiguration (SessionStateQueries)

- (FBSimulatorBinary *)binary;

@end

@implementation FBProcessLaunchConfiguration (SessionStateQueries)

- (FBSimulatorBinary *)binary
{
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

@end

@implementation FBApplicationLaunchConfiguration (SessionStateQueries)

- (FBSimulatorBinary *)binary
{
  return self.application.binary;
}

@end

@implementation FBAgentLaunchConfiguration (SessionStateQueries)

- (FBSimulatorBinary *)binary
{
  return self.agentBinary;
}

@end

@implementation FBSimulatorHistory (Queries)

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

- (NSArray *)allLaunchedApplications
{
  return [self.allUserLaunchedProcesses filteredArrayUsingPredicate:FBSimulatorHistory.predicateForUserLaunchedApplications];
}

- (NSArray *)allLaunchedAgents
{
  return [self.allUserLaunchedProcesses filteredArrayUsingPredicate:FBSimulatorHistory.predicateForUserLaunchedAgents];
}

- (FBProcessInfo *)lastLaunchedApplicationProcess
{
  // launchedProcesses has last event based ordering. Message-to-nil will return immediately in base-case.
  return self.runningApplications.firstObject ?: [self.previousState lastLaunchedApplicationProcess];
}

- (FBApplicationLaunchConfiguration *)lastLaunchedApplication
{
  return self.processLaunchConfigurations[self.lastLaunchedApplicationProcess];
}

- (FBProcessInfo *)lastLaunchedAgent
{
  // launchedProcesses has last event based ordering. Message-to-nil will return immediately in base-case.
  return self.runningAgents.firstObject ?: [self.previousState lastLaunchedAgent];
}

- (FBProcessInfo *)runningProcessForLaunchConfiguration:(FBProcessLaunchConfiguration *)launchConfig
{
  return [self runningProcessForBinary:launchConfig.binary];
}

- (FBProcessInfo *)runningProcessForBinary:(FBSimulatorBinary *)binary
{
  return [[self.runningApplications
    filteredArrayUsingPredicate:[FBSimulatorHistory predicateForBinary:binary]]
    firstObject];
}

- (FBProcessInfo *)runningProcessForApplication:(FBSimulatorApplication *)application
{
  return [self runningProcessForApplication:application recursive:NO];
}

- (NSArray *)runningAgents
{
  return [self.launchedProcesses filteredArrayUsingPredicate:FBSimulatorHistory.predicateForUserLaunchedAgents];
}

- (NSArray *)runningApplications
{
  return [self.launchedProcesses filteredArrayUsingPredicate:FBSimulatorHistory.predicateForUserLaunchedApplications];
}

- (id)diagnosticNamed:(NSString *)name forApplication:(FBSimulatorApplication *)application
{
  FBProcessInfo *processInfo = [self runningProcessForApplication:application recursive:YES];
  return self.processDiagnostics[processInfo][name];
}

- (NSArray *)changesToSimulatorState
{
  return [self changesToKeyPath:@"simulatorState"];
}

- (NSDate *)sessionStartDate
{
  return self.firstSessionState.timestamp;
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

- (instancetype)firstSessionState
{
  if (self.previousState == nil) {
    return self;
  }
  return self.previousState.firstSessionState;
}

#pragma mark Predicates

+ (NSPredicate *)predicateForBinary:(FBSimulatorBinary *)binary
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
    return [process.launchPath isEqualToString:binary.path];
  }];
}

+ (NSPredicate *)predicateForUserLaunchedApplications
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
    return [process.launchPath rangeOfString:@".app"].location != NSNotFound;
  }];
}

+ (NSPredicate *)predicateForUserLaunchedAgents
{
  return [NSCompoundPredicate notPredicateWithSubpredicate:
    [self predicateForUserLaunchedApplications]
  ];
}

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSessionState+Queries.h"

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

@implementation FBSimulatorSessionState (Queries)

- (NSArray *)allUserLaunchedProcesses
{
  NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSet];
  FBSimulatorSessionState *state = self;
  while (state) {
    [set addObjectsFromArray:state.runningProcesses];
    state = state.previousState;
  }
  return [set array];
}

- (NSArray *)allLaunchedApplications
{
  return [self.allUserLaunchedProcesses filteredArrayUsingPredicate:self.predicateForUserLaunchedApplications];
}

- (NSArray *)allLaunchedAgents
{
  return [self.allUserLaunchedProcesses filteredArrayUsingPredicate:self.predicateForUserLaunchedAgents];
}

- (FBApplicationLaunchConfiguration *)lastLaunchedApplication
{
  // runningProcesses has last event based ordering. Message-to-nil will return immediately in base-case.
  return (FBApplicationLaunchConfiguration *)[self.runningApplications.firstObject launchConfiguration] ?: [self.previousState lastLaunchedApplication];
}

- (FBAgentLaunchConfiguration *)lastLaunchedAgent
{
  // runningProcesses has last event based ordering. Message-to-nil will return immediately in base-case.
  return (FBAgentLaunchConfiguration *)[self.runningAgents.firstObject launchConfiguration] ?: [self.previousState lastLaunchedAgent];
}

- (FBUserLaunchedProcess *)runningProcessForLaunchConfiguration:(FBProcessLaunchConfiguration *)launchConfig
{
  for (FBUserLaunchedProcess *state in self.runningProcesses) {
    if ([state.launchConfiguration isEqual:launchConfig]) {
      return state;
    }
  }
  return nil;
}

- (FBUserLaunchedProcess *)runningProcessForBinary:(FBSimulatorBinary *)binary
{
  for (FBUserLaunchedProcess *state in self.runningProcesses) {
    if ([state.launchConfiguration.binary isEqual:binary]) {
      return state;
    }
  }
  return nil;
}

- (FBUserLaunchedProcess *)runningProcessForApplication:(FBSimulatorApplication *)application
{
  return [self runningProcessForApplication:application recursive:NO];
}

- (NSArray *)runningAgents
{
  return [self.runningProcesses filteredArrayUsingPredicate:self.predicateForUserLaunchedAgents];
}

- (NSArray *)runningApplications
{
  return [self.runningProcesses filteredArrayUsingPredicate:self.predicateForUserLaunchedApplications];
}

- (id)diagnosticNamed:(NSString *)name forApplication:(FBSimulatorApplication *)application
{
  return [self runningProcessForApplication:application recursive:YES].diagnostics[name];
}

- (NSDictionary *)allProcessDiagnostics;
{
  NSMutableDictionary *diagnostics = [NSMutableDictionary dictionary];
  [diagnostics addEntriesFromDictionary:self.previousState.allProcessDiagnostics ?: @{}];
  for (FBUserLaunchedProcess *processState in self.runningProcesses) {
    [diagnostics addEntriesFromDictionary:processState.diagnostics];
  }
  return [diagnostics copy];
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
  FBSimulatorSessionState *state = self;
  id value = [state valueForKeyPath:keyPath];
  NSMutableArray *array = [NSMutableArray array];
  [array addObject:state];

  while (state) {
    id nextValue = [state valueForKeyPath:keyPath];
    if (![value isEqual:nextValue]) {
      [array addObject:state];
    }
    value = nextValue;
    state = state.previousState;
  }

  return [array copy];
}

- (FBUserLaunchedProcess *)runningProcessForApplication:(FBSimulatorApplication *)application recursive:(BOOL)recursive
{
  for (FBUserLaunchedProcess *state in self.runningApplications) {
    if ([state.launchConfiguration.binary isEqual:application.binary]) {
      return state;
    }
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

- (NSPredicate *)predicateForUserLaunchedApplications
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBUserLaunchedProcess *process, NSDictionary *_) {
    return [process.launchConfiguration isKindOfClass:FBApplicationLaunchConfiguration.class];
  }];
}

- (NSPredicate *)predicateForUserLaunchedAgents
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBUserLaunchedProcess *process, NSDictionary *_) {
    return [process.launchConfiguration isKindOfClass:FBAgentLaunchConfiguration.class];
  }];
}

@end

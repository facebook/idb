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

- (FBUserLaunchedProcess *)processForLaunchConfiguration:(FBProcessLaunchConfiguration *)launchConfig
{
  for (FBUserLaunchedProcess *state in self.runningProcesses) {
    if ([state.launchConfiguration isEqual:launchConfig]) {
      return state;
    }
  }
  return nil;
}

- (FBUserLaunchedProcess *)processForBinary:(FBSimulatorBinary *)binary
{
  for (FBUserLaunchedProcess *state in self.runningProcesses) {
    if ([state.launchConfiguration.binary isEqual:binary]) {
      return state;
    }
  }
  return nil;
}

- (FBUserLaunchedProcess *)processForApplication:(FBSimulatorApplication *)application
{
  return [self processForApplication:application recursive:NO];
}

- (NSArray *)runningAgents
{
  NSMutableArray *agents = [NSMutableArray array];
  for (FBUserLaunchedProcess *state in self.runningProcesses) {
    if ([state.launchConfiguration isKindOfClass:FBAgentLaunchConfiguration.class]) {
      [agents addObject:state];
    }
  }
  return [agents copy];
}

- (NSArray *)runningApplications
{
  NSMutableArray *applications = [NSMutableArray array];
  for (FBUserLaunchedProcess *state in self.runningProcesses) {
    if ([state.launchConfiguration isKindOfClass:FBApplicationLaunchConfiguration.class]) {
      [applications addObject:state];
    }
  }
  return [applications copy];
}

- (id)diagnosticNamed:(NSString *)name forApplication:(FBSimulatorApplication *)application
{
  return [self processForApplication:application recursive:YES].diagnostics[name];
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

- (FBUserLaunchedProcess *)processForApplication:(FBSimulatorApplication *)application recursive:(BOOL)recursive
{
  for (FBUserLaunchedProcess *state in self.runningApplications) {
    if ([state.launchConfiguration.binary isEqual:application.binary]) {
      return state;
    }
  }
  return recursive ? [self.previousState processForApplication:application recursive:recursive] : nil;
}

@end

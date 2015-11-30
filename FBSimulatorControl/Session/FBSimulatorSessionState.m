/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSessionState.h"
#import "FBSimulatorSessionState+Private.h"

#import "FBProcessLaunchConfiguration.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorSession.h"

@implementation FBSimulatorSessionState

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _lifecycle = FBSimulatorSessionLifecycleStateNotStarted;
  _timestamp = [NSDate date];
  _runningProcessesSet = [NSMutableOrderedSet orderedSet];
  _mutableDiagnostics = [NSMutableDictionary dictionary];
  return self;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBSimulatorSessionState *state = [self.class new];
  state.session = self.session;
  state.lifecycle = self.lifecycle;
  state.timestamp = self.timestamp;
  state.simulatorState = self.simulatorState;
  state.previousState = self.previousState;
  state.runningProcessesSet = [self.runningProcessesSet mutableCopy];
  state.mutableDiagnostics = [self.mutableDiagnostics mutableCopy];
  return state;
}

- (FBSimulator *)simulator
{
  return self.session.simulator;
}

- (NSArray *)runningProcesses
{
  return self.runningProcessesSet.array;
}

- (NSDictionary *)diagnostics
{
  return [self.mutableDiagnostics copy];
}

- (NSUInteger)hash
{
  // Session has reference based equality so it is sufficient for hashing.
  return self.session.hash |
         self.runningProcesses.hash |
         self.timestamp.hash |
         (unsigned long) self.simulatorState |
         self.lifecycle |
         self.mutableDiagnostics.hash;
}

- (BOOL)isEqual:(FBSimulatorSessionState *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return ((self.previousState == nil && object.previousState == nil) || [self.previousState isEqual:object.previousState]) &&
         self.session == object.session &&
         [self.timestamp isEqual:object.timestamp] &&
         self.lifecycle == object.lifecycle &&
         self.simulatorState == object.simulatorState &&
         [self.runningProcesses isEqual:object.runningProcesses] &&
         [self.mutableDiagnostics isEqualToDictionary:object.mutableDiagnostics];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Session %@ | Change %@",
    self.session,
    [FBSimulatorSessionState describeDifferenceBetween:self and:self.previousState]
  ];
}

- (NSString *)recursiveChangeDescription
{
  NSMutableString *string = [NSMutableString string];
  FBSimulatorSessionState *state = self;
  while (state) {
    if (string.length > 0) {
      [string appendString:@"\n"];
    }

    [string appendFormat:
      @"Device %@ | Change %@",
      self.simulator.udid,
      [FBSimulatorSessionState describeDifferenceBetween:state and:state.previousState]
     ];
    state = state.previousState;
  }
  return [string copy];
}

+ (NSString *)stringForLifecycleState:(FBSimulatorSessionLifecycleState)lifecycleState
{
  if (lifecycleState == FBSimulatorSessionLifecycleStateNotStarted) {
    return @"Not Started";
  }
  if (lifecycleState == FBSimulatorSessionLifecycleStateStarted) {
    return @"Started";
  }
  if (lifecycleState == FBSimulatorSessionLifecycleStateEnded) {
    return @"End";
  }
  return @"Unknown";
}

+ (NSString *)describeDifferenceBetween:(FBSimulatorSessionState *)first and:(FBSimulatorSessionState *)second
{
  if (first && !second) {
    return @"Inital State";
  }

  NSMutableString *string = [NSMutableString string];
  if (first.lifecycle != second.lifecycle) {
    [string appendFormat:
      @"Lifecycle from %@ to %@ | ",
      [FBSimulatorSessionState stringForLifecycleState:second.lifecycle],
      [FBSimulatorSessionState stringForLifecycleState:first.lifecycle]
    ];
  }
  if (first.simulatorState != second.simulatorState) {
    [string appendFormat:
      @"Simulator State from %@ to %@ | ",
      [FBSimulator stateStringFromSimulatorState:second.simulatorState],
      [FBSimulator stateStringFromSimulatorState:first.simulatorState]
    ];
  }
  if (![first.runningProcessesSet isEqual:second.runningProcessesSet]) {
    [string appendFormat:@"Running Processes from %@ to %@ | ", second.runningProcessesSet, first.runningProcessesSet];
  }
  if (![first.mutableDiagnostics isEqualToDictionary:second.mutableDiagnostics]) {
    [string appendFormat:@"Diagnostics from %@ to %@ | ", second.mutableDiagnostics, first.mutableDiagnostics];
  }
  if (string.length == 0) {
    return @"No Changes";
  }
  [string appendFormat:@"At Date %@", second.timestamp];
  return string;
}

@end

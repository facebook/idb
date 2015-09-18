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

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBSimulatorSessionState *state = [self.class new];
  state.session = self.session;
  state.lifecycle = self.lifecycle;
  state.timestamp = self.timestamp;
  state.simulatorState = self.simulatorState;
  state.previousState = self.previousState;
  state.runningProcessesSet = [self.runningProcessesSet mutableCopy];
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

- (NSUInteger)hash
{
  // Session has reference based equality so it is sufficient for hashing.
  return self.session.hash |
         self.runningProcesses.hash |
         self.timestamp.hash |
         self.simulatorState |
         self.lifecycle;
}

- (BOOL)isEqual:(FBSimulatorSessionState *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return self.session == object.session &&
         ((self.session == nil && object.session == nil) || [self.previousState isEqual:object.previousState]) &&
         [self.timestamp isEqual:object.timestamp] &&
         self.lifecycle == object.lifecycle &&
         self.simulatorState == object.simulatorState &&
         [self.runningProcesses isEqual:object.runningProcesses];
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
  if (![first.runningProcesses isEqual:second.runningProcesses]) {
    [string appendFormat:@"Running Processes from %@ to %@ | ", second.runningProcesses, first.runningProcesses];
  }
  if (string.length == 0) {
    return @"No Changes";
  }
  [string appendFormat:@"At Date %@", second.timestamp];
  return string;
}

@end

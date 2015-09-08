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

@implementation FBSimulatorSessionProcessState

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBSimulatorSessionProcessState *state = [self.class new];
  state.processIdentifier = self.processIdentifier;
  state.launchConfiguration = self.launchConfiguration;
  state.launchDate = self.launchDate;
  state.diagnostics = self.diagnostics;
  return state;
}

- (NSUInteger)hash
{
  return self.processIdentifier | self.launchConfiguration.hash | self.launchConfiguration.hash | self.diagnostics.hash;
}

- (BOOL)isEqual:(FBSimulatorSessionProcessState *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return self.processIdentifier == object.processIdentifier &&
         [self.launchConfiguration isEqual:object.launchConfiguration] &&
         [self.launchDate isEqual:object.launchDate] &&
         [self.diagnostics isEqual:object.diagnostics];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Launch %@ | PID %ld | Launched %@ | Diagnositcs %@",
    self.launchConfiguration,
    self.processIdentifier,
    self.launchDate,
    self.diagnostics
  ];
}

@end

@implementation FBSimulatorSessionState

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBSimulatorSessionState *state = [self.class new];
  state.session = self.session;
  state.lifecycle = self.lifecycle;
  state.runningProcessesSet = [self.runningProcessesSet mutableCopy];
  state.previousState = self.previousState;
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
  return self.runningProcesses.hash | self.runningProcesses.hash | self.session.hash | self.lifecycle;
}

- (BOOL)isEqual:(FBSimulatorSessionState *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return self.session == object.session &&
         self.lifecycle == self.lifecycle &&
         [self.runningProcesses isEqual:object.runningProcesses] &&
         [self.previousState isEqual:object.previousState];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Session %@ | Running Processes %@",
    self.session,
    self.runningProcessesSet
  ];
}

@end

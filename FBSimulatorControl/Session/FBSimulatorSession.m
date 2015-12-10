/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSession.h"
#import "FBSimulatorSession+Private.h"
#import "FBSimulatorSessionState+Private.h"

#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction.h"
#import "FBSimulatorLogs.h"
#import "FBSimulatorSessionLifecycle.h"
#import "FBSimulatorSessionState.h"

@implementation FBSimulatorSession

#pragma mark - Initializers

+ (instancetype)sessionWithSimulator:(FBSimulator *)simulator
{
  NSParameterAssert(simulator);

  FBSimulatorSession *session = [[FBSimulatorSession alloc] initWithSimulator:simulator];
  simulator.session = session;
  return session;
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _lifecycle = [FBSimulatorSessionLifecycle lifecycleWithSession:self];
  return self;
}

#pragma mark - Public Interface

- (BOOL)terminateWithError:(NSError **)error
{
  if (self.state.lifecycle == FBSimulatorSessionLifecycleStateEnded) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot Terminate an already Ended session" errorOut:error];
  }
  [self.lifecycle didEndSession];
  return [self.simulator freeFromPoolWithError:error];
}

- (FBSimulatorSessionState *)state
{
  return self.lifecycle.currentState;
}

- (FBSimulatorSessionLogs *)logs
{
  return [FBSimulatorSessionLogs withSession:self];
}

- (FBSimulatorInteraction *)interact;
{
  return [FBSimulatorInteraction withSimulator:self.simulator lifecycle:self.lifecycle];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Session: Simulator %@",
    self.simulator
  ];
}

@end

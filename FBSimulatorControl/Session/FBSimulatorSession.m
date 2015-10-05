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

#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorSessionInteraction.h"
#import "FBSimulatorSessionLifecycle.h"
#import "FBSimulatorSessionState.h"

@implementation FBSimulatorSession

#pragma mark - Initializers

+ (instancetype)sessionWithSimulator:(FBSimulator *)simulator
{
  NSParameterAssert(simulator);

  return [[FBSimulatorSession alloc] initWithSimulator:simulator];
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

- (FBSimulatorSessionInteraction *)interact;
{
  return [FBSimulatorSessionInteraction builderWithSession:self];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Session: Simulator %@",
    self.simulator
  ];
}

@end

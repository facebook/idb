/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorMutableState.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulatorAgentOperation.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorApplicationOperation.h"

@interface FBSimulatorMutableState ()

@property (nonatomic, copy, readwrite) FBProcessInfo *launchdProcess;
@property (nonatomic, copy, readwrite) FBProcessInfo *containerApplication;

@property (nonatomic, assign, readwrite) FBiOSTargetState lastKnownState;
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> sink;

@end

@implementation FBSimulatorMutableState

- (instancetype)initWithLaunchdProcess:(nullable FBProcessInfo *)launchdProcess containerApplication:(nullable FBProcessInfo *)containerApplication sink:(id<FBSimulatorEventSink>)sink
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _launchdProcess = launchdProcess;
  _containerApplication = containerApplication;
  _sink = sink;
  _lastKnownState = FBiOSTargetStateUnknown;

  return self;
}

#pragma mark FBSimulatorEventSink Protocol Implementation

- (void)containerApplicationDidLaunch:(FBProcessInfo *)applicationProcess
{
  NSParameterAssert(applicationProcess);

  // If we have Application-centric Launch Info, deduplicate.
  if (self.containerApplication) {
    return;
  }
  self.containerApplication = applicationProcess;
  [self.sink containerApplicationDidLaunch:applicationProcess];
}

- (void)containerApplicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  NSParameterAssert(applicationProcess);

  // De-duplicate known-terminated Simulators.
  if (!self.containerApplication) {
    return;
  }
  self.containerApplication = nil;
  [self.sink containerApplicationDidTerminate:applicationProcess expected:expected];
}

- (void)connectionDidConnect:(FBSimulatorConnection *)connection
{
  NSParameterAssert(connection);
  [self.sink connectionDidConnect:connection];
}

- (void)connectionDidDisconnect:(FBSimulatorConnection *)connection expected:(BOOL)expected
{
  NSParameterAssert(connection);
  [self.sink connectionDidDisconnect:connection expected:expected];
}

- (void)simulatorDidLaunch:(FBProcessInfo *)launchdProcess
{
  NSParameterAssert(launchdProcess);

  // De-duplicate known-launched launchd_sims.
  if (self.launchdProcess) {
    return;
  }
  self.launchdProcess = launchdProcess;
  [self.sink simulatorDidLaunch:launchdProcess];
}

- (void)simulatorDidTerminate:(FBProcessInfo *)launchdProcess expected:(BOOL)expected
{
  NSParameterAssert(launchdProcess);

  // De-duplicate known-terminated launchd_sims.
  if (!self.launchdProcess) {
    return;
  }
  self.launchdProcess = nil;
  [self.sink simulatorDidTerminate:launchdProcess expected:expected];
}

- (void)agentDidLaunch:(FBSimulatorAgentOperation *)operation
{
  [self.sink agentDidLaunch:operation];
}

- (void)agentDidTerminate:(FBSimulatorAgentOperation *)operation statLoc:(int)statLoc
{
  [self.sink agentDidTerminate:operation statLoc:statLoc];
}

- (void)applicationDidLaunch:(FBSimulatorApplicationOperation *)operation
{
  [self.sink applicationDidLaunch:operation];
}

- (void)applicationDidTerminate:(FBSimulatorApplicationOperation *)operation expected:(BOOL)expected
{
  [self.sink applicationDidTerminate:operation expected:expected];
}

- (void)didChangeState:(FBiOSTargetState)state
{
  if (state == self.lastKnownState) {
    return;
  }

  self.lastKnownState = state;
  [self.sink didChangeState:state];
}

@end

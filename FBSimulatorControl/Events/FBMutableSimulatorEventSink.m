/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBMutableSimulatorEventSink.h"

@implementation FBMutableSimulatorEventSink

- (void)containerApplicationDidLaunch:(FBProcessInfo *)applicationProcess
{
  [self.eventSink containerApplicationDidLaunch:applicationProcess];
}

- (void)containerApplicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self.eventSink containerApplicationDidTerminate:applicationProcess expected:expected];
}

- (void)connectionDidConnect:(FBSimulatorConnection *)connection
{
  [self.eventSink connectionDidConnect:connection];
}

- (void)connectionDidDisconnect:(FBSimulatorConnection *)connection expected:(BOOL)expected
{
  [self.eventSink connectionDidDisconnect:connection expected:expected];
}

- (void)simulatorDidLaunch:(FBProcessInfo *)launchdProcess
{
  [self.eventSink simulatorDidLaunch:launchdProcess];
}

- (void)simulatorDidTerminate:(FBProcessInfo *)launchdProcess expected:(BOOL)expected
{
  [self.eventSink simulatorDidTerminate:launchdProcess expected:expected];
}

- (void)agentDidLaunch:(FBSimulatorAgentOperation *)operation
{
  [self.eventSink agentDidLaunch:operation];
}

- (void)agentDidTerminate:(FBSimulatorAgentOperation *)operation statLoc:(int)statLoc
{
  [self.eventSink agentDidTerminate:operation statLoc:statLoc];
}

- (void)applicationDidLaunch:(FBSimulatorApplicationOperation *)operation
{
  [self.eventSink applicationDidLaunch:operation];
}

- (void)applicationDidTerminate:(FBSimulatorApplicationOperation *)operation expected:(BOOL)expected
{
  [self.eventSink applicationDidTerminate:operation expected:expected];
}

- (void)didChangeState:(FBiOSTargetState)state
{
  [self.eventSink didChangeState:state];
}

@end

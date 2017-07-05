/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess
{
  [self.eventSink applicationDidLaunch:launchConfig didStart:applicationProcess];
}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self.eventSink applicationDidTerminate:applicationProcess expected:expected];
}

- (void)testmanagerDidConnect:(FBTestManager *)testManager
{
  [self.eventSink testmanagerDidConnect:testManager];
}

- (void)testmanagerDidDisconnect:(FBTestManager *)testManager
{
  [self.eventSink testmanagerDidDisconnect:testManager];
}

- (void)diagnosticAvailable:(FBDiagnostic *)diagnostic
{
  [self.eventSink diagnosticAvailable:diagnostic];
}

- (void)didChangeState:(FBSimulatorState)state
{
  [self.eventSink didChangeState:state];
}

- (void)terminationHandleAvailable:(id<FBTerminationHandle>)terminationHandle
{
  [self.eventSink terminationHandleAvailable:terminationHandle];
}

@end

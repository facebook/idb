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

- (void)bridgeDidConnect:(FBSimulatorBridge *)bridge
{
  [self.eventSink bridgeDidConnect:bridge];
}

- (void)bridgeDidDisconnect:(FBSimulatorBridge *)bridge expected:(BOOL)expected
{
  [self.eventSink bridgeDidDisconnect:bridge expected:expected];
}

- (void)simulatorDidLaunch:(FBProcessInfo *)launchdSimProcess
{
  [self.eventSink simulatorDidLaunch:launchdSimProcess];
}

- (void)simulatorDidTerminate:(FBProcessInfo *)launchdSimProcess expected:(BOOL)expected
{
  [self.eventSink simulatorDidTerminate:launchdSimProcess expected:expected];
}

- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)agentProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self.eventSink agentDidLaunch:launchConfig didStart:agentProcess stdOut:stdOut stdErr:stdErr];
}

- (void)agentDidTerminate:(FBProcessInfo *)agentProcess expected:(BOOL)expected
{
  [self.eventSink agentDidTerminate:agentProcess expected:expected];
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

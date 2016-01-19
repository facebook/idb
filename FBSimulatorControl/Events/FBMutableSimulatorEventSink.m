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

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self.eventSink applicationDidLaunch:launchConfig didStart:applicationProcess stdOut:stdOut stdErr:stdErr];
}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self.eventSink applicationDidTerminate:applicationProcess expected:expected];
}

- (void)diagnosticInformationAvailable:(NSString *)name process:(FBProcessInfo *)process value:(id<NSCopying, NSCoding>)value
{
  [self.eventSink diagnosticInformationAvailable:name process:process value:value];
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

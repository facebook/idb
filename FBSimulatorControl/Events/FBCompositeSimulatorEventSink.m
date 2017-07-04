/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBCompositeSimulatorEventSink.h"

@interface FBCompositeSimulatorEventSink ()

@property (nonatomic, copy, readwrite) NSArray<id<FBSimulatorEventSink>> *sinks;

@end

@implementation FBCompositeSimulatorEventSink

+ (instancetype)withSinks:(NSArray<id<FBSimulatorEventSink>> *)sinks;
{
  return [[FBCompositeSimulatorEventSink alloc] initWithSinks:sinks];
}

- (instancetype)initWithSinks:(NSArray<id<FBSimulatorEventSink>> *)sinks;
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _sinks = sinks;

  return self;
}

- (void)containerApplicationDidLaunch:(FBProcessInfo *)applicationProcess
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink containerApplicationDidLaunch:applicationProcess];
  }
}

- (void)containerApplicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink containerApplicationDidTerminate:applicationProcess expected:expected];
  }
}

- (void)connectionDidConnect:(FBSimulatorConnection *)connection
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink connectionDidConnect:connection];
  }
}

- (void)connectionDidDisconnect:(FBSimulatorConnection *)connection expected:(BOOL)expected
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink connectionDidDisconnect:connection expected:expected];
  }
}

- (void)simulatorDidLaunch:(FBProcessInfo *)launchdProcess
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink simulatorDidLaunch:launchdProcess];
  }
}

- (void)simulatorDidTerminate:(FBProcessInfo *)launchdProcess expected:(BOOL)expected
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink simulatorDidTerminate:launchdProcess expected:expected];
  }
}

- (void)agentDidLaunch:(FBSimulatorAgentOperation *)operation
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink agentDidLaunch:operation];
  }
}

- (void)agentDidTerminate:(FBSimulatorAgentOperation *)operation statLoc:(int)statLoc
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink agentDidTerminate:operation statLoc:statLoc];
  }
}

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink applicationDidLaunch:launchConfig didStart:applicationProcess];
  }
}

- (void)applicationDidTerminate:(FBProcessInfo *)processInfo expected:(BOOL)expected
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink applicationDidTerminate:processInfo expected:expected];
  }
}

- (void)testmanagerDidConnect:(FBTestManager *)testManager
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink testmanagerDidConnect:testManager];
  }
}

- (void)testmanagerDidDisconnect:(FBTestManager *)testManager
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink testmanagerDidDisconnect:testManager];
  }
}

- (void)diagnosticAvailable:(FBDiagnostic *)diagnostic
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink diagnosticAvailable:diagnostic];
  }
}

- (void)didChangeState:(FBSimulatorState)state
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink didChangeState:state];
  }
}

- (void)terminationHandleAvailable:(id<FBTerminationHandle>)terminationHandle
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink terminationHandleAvailable:terminationHandle];
  }
}

@end

/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

- (void)applicationDidLaunch:(FBSimulatorApplicationOperation *)operation
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink applicationDidLaunch:operation];
  }
}

- (void)applicationDidTerminate:(FBSimulatorApplicationOperation *)operation expected:(BOOL)expected
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink applicationDidTerminate:operation expected:expected];
  }
}

- (void)didChangeState:(FBiOSTargetState)state
{
  for (id<FBSimulatorEventSink> sink in self.sinks) {
    [sink didChangeState:state];
  }
}

@end

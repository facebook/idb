/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLoggingEventSink.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"

@interface FBSimulatorLoggingEventSink ()

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBSimulatorLoggingEventSink

#pragma mark Initializers

+ (instancetype)withSimulator:(FBSimulator *)simulator logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithLogger:[logger withPrefix:[NSString stringWithFormat:@"%@:", simulator.udid]]];
}

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logger = logger;

  return self;
}

#pragma mark FBSimulatorEventSink Implementation

- (void)containerApplicationDidLaunch:(FBProcessInfo *)applicationProcess
{
  [self.logger logFormat:@"Container Application Did Launch => %@", applicationProcess.shortDescription];
}

- (void)containerApplicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self.logger logFormat:@"Container Application Did Terminate => %@ Expected %d", applicationProcess.shortDescription, expected];
}

- (void)bridgeDidConnect:(FBSimulatorBridge *)bridge
{
  [self.logger logFormat:@"Bridge Did Connect => %@", bridge];
}

- (void)bridgeDidDisconnect:(FBSimulatorBridge *)bridge expected:(BOOL)expected
{
  [self.logger logFormat:@"Bridge Did Disconnect => %@ Expected %d", bridge, expected];
}

- (void)simulatorDidLaunch:(FBProcessInfo *)launchdSimProcess
{
  [self.logger logFormat:@"Simulator Did launch => %@", launchdSimProcess.shortDescription];
}

- (void)simulatorDidTerminate:(FBProcessInfo *)launchdSimProcess expected:(BOOL)expected
{
  [self.logger logFormat:@"Simulator Did Terminate => %@ Expected %d", launchdSimProcess.shortDescription, expected];
}

- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)agentProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self.logger logFormat:@"Agent Did Launch => %@", agentProcess.shortDescription];
}

- (void)agentDidTerminate:(FBProcessInfo *)agentProcess expected:(BOOL)expected
{
  [self.logger logFormat:@"Agent Did Terminate => Expected %d %@", expected, agentProcess.shortDescription];
}

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess
{
  [self.logger logFormat:@"Application Did Launch => %@", applicationProcess.shortDescription];
}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self.logger logFormat:@"Application Did Terminate => Expected %d %@", expected, applicationProcess.shortDescription];
}

- (void)testmanagerDidConnect:(FBTestManager *)testManager
{
  [self.logger logFormat:@"TestManager Did Connect => %@", testManager];
}

- (void)testmanagerDidDisconnect:(FBTestManager *)testManager
{
  [self.logger logFormat:@"TestManager Did Disconnect => %@", testManager];
}

- (void)diagnosticAvailable:(FBDiagnostic *)diagnostic
{
  [self.logger logFormat:@"Log Available => %@", diagnostic.shortDescription];
}

- (void)didChangeState:(FBSimulatorState)state
{
  [self.logger logFormat:@"Did Change State => %@", [FBSimulator stateStringFromSimulatorState:state]];
}

- (void)terminationHandleAvailable:(id<FBTerminationHandle>)terminationHandle
{

}

@end

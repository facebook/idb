/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLoggingEventSink.h"

#import "FBProcessInfo.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorControlGlobalConfiguration.h"
#import "FBDiagnostic.h"

@interface FBSimulatorLoggingEventSink ()

@property (nonatomic, strong, readonly) id<FBSimulatorLogger> logger;

@end

@implementation FBSimulatorLoggingEventSink

#pragma mark Initializers

+ (instancetype)withSimulator:(FBSimulator *)simulator logger:(id<FBSimulatorLogger>)logger
{
  return [[self alloc] initWithLogger:[logger withPrefix:[NSString stringWithFormat:@"%@:", simulator.udid]]];
}

- (instancetype)initWithLogger:(id<FBSimulatorLogger>)logger
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

- (void)framebufferDidStart:(FBSimulatorFramebuffer *)framebuffer
{
  [self.logger logFormat:@"Framebuffer Did Start => %@", framebuffer];
}

- (void)framebufferDidTerminate:(FBSimulatorFramebuffer *)framebuffer expected:(BOOL)expected
{
  [self.logger logFormat:@"Framebuffer Did Terminate => %@ Expected %d", framebuffer, expected];
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

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self.logger logFormat:@"Application Did Launch => %@", applicationProcess.shortDescription];
}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self.logger logFormat:@"Application Did Terminate => Expected %d %@", expected, applicationProcess.shortDescription];
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

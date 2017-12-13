/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorEventRelay.h"

#import <Cocoa/Cocoa.h>

#import <FBControlCore/FBControlCore.h>

#import "FBCoreSimulatorNotifier.h"
#import "FBSimulatorAgentOperation.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorProcessFetcher.h"
#import "FBSimulatorApplicationOperation.h"

@interface FBSimulatorEventRelay ()

@property (nonatomic, copy, readwrite) FBProcessInfo *launchdProcess;
@property (nonatomic, copy, readwrite) FBProcessInfo *containerApplication;
@property (nonatomic, strong, readwrite) FBSimulatorConnection *connection;

@property (nonatomic, assign, readwrite) FBSimulatorState lastKnownState;
@property (nonatomic, strong, readonly) NSMutableSet *knownLaunchedProcesses;
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> sink;

@end

@implementation FBSimulatorEventRelay

- (instancetype)initWithLaunchdProcess:(nullable FBProcessInfo *)launchdProcess containerApplication:(nullable FBProcessInfo *)containerApplication sink:(id<FBSimulatorEventSink>)sink
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _launchdProcess = launchdProcess;
  _containerApplication = containerApplication;
  _sink = sink;

  _knownLaunchedProcesses = [NSMutableSet set];
  _lastKnownState = FBSimulatorStateUnknown;

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
  NSParameterAssert(self.connection == nil);

  self.connection = connection;
  [self.sink connectionDidConnect:connection];
}

- (void)connectionDidDisconnect:(FBSimulatorConnection *)connection expected:(BOOL)expected
{
  NSParameterAssert(connection);
  NSParameterAssert(self.connection);

  self.connection = nil;
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
  // De-duplicate known-launched agents.
  FBProcessInfo *agentProcess = operation.process;
  if ([self.knownLaunchedProcesses containsObject:agentProcess]) {
    return;
  }

  [self.knownLaunchedProcesses addObject:agentProcess];
  [self.sink agentDidLaunch:operation];
}

- (void)agentDidTerminate:(FBSimulatorAgentOperation *)operation statLoc:(int)statLoc
{
  if (![self.knownLaunchedProcesses containsObject:operation.process]) {
    return;
  }

  [self.sink agentDidTerminate:operation statLoc:statLoc];
}

- (void)applicationDidLaunch:(FBSimulatorApplicationOperation *)operation
{
  // De-duplicate known-launched applications.
  FBProcessInfo *applicationProcess = operation.process;
  if ([self.knownLaunchedProcesses containsObject:applicationProcess]) {
    return;
  }

  [self.knownLaunchedProcesses addObject:applicationProcess];
  [self.sink applicationDidLaunch:operation];
}

- (void)applicationDidTerminate:(FBSimulatorApplicationOperation *)operation expected:(BOOL)expected
{
  FBProcessInfo *applicationProcess = operation.process;
  if (![self.knownLaunchedProcesses containsObject:applicationProcess]) {
    return;
  }

  [self.knownLaunchedProcesses removeObject:applicationProcess];
  [self.sink applicationDidTerminate:operation expected:expected];
}

- (void)diagnosticAvailable:(FBDiagnostic *)diagnostic
{
  [self.sink diagnosticAvailable:diagnostic];
}

- (void)didChangeState:(FBSimulatorState)state
{
  if (state == self.lastKnownState) {
    return;
  }

  self.lastKnownState = state;
  [self.sink didChangeState:state];
}

@end

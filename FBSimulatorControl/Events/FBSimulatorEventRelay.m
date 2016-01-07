/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorEventRelay.h"

#import <AppKit/AppKit.h>

#import <CoreSimulator/SimDevice.h>

#import "FBCoreSimulatorNotifier.h"
#import "FBDispatchSourceNotifier.h"
#import "FBProcessInfo.h"
#import "FBProcessQuery+Simulators.h"
#import "FBProcessQuery.h"
#import "FBSimulatorControlGlobalConfiguration.h"
#import "FBSimulatorLaunchInfo.h"

@interface FBSimulatorEventRelay ()

@property (nonatomic, copy, readwrite) FBSimulatorLaunchInfo *launchInfo;
@property (nonatomic, assign, readwrite) FBSimulatorState lastKnownState;
@property (nonatomic, strong, readonly) NSMutableSet *knownLaunchedProcesses;

@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> sink;
@property (nonatomic, strong, readonly) FBProcessQuery *processQuery;
@property (nonatomic, strong, readonly) SimDevice *simDevice;

@property (nonatomic, strong, readonly) NSMutableDictionary *processTerminationNotifiers;
@property (nonatomic, strong, readwrite) FBCoreSimulatorNotifier *stateChangeNotifier;

@end

@implementation FBSimulatorEventRelay

- (instancetype)initWithSimDevice:(SimDevice *)simDevice processQuery:(FBProcessQuery *)processQuery sink:(id<FBSimulatorEventSink>)sink
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _sink = sink;
  _simDevice = simDevice;
  _processQuery = processQuery;
  _launchInfo = [FBSimulatorLaunchInfo launchedViaApplicationOfSimDevice:simDevice query:processQuery];
  _processTerminationNotifiers = [NSMutableDictionary dictionary];
  _knownLaunchedProcesses = [NSMutableSet set];
  _lastKnownState = FBSimulatorStateUnknown;

  [self registerSimulatorLifecycleHandlers];
  [self createNotifierForSimDevice:simDevice];

  return self;
}

- (void)dealloc
{
  [self unregisterAllNotifiers];
  [self unregisterSimulatorLifecycleHandlers];
}

#pragma mark FBSimulatorEventSink Protocol Implementation

- (void)didStartWithLaunchInfo:(FBSimulatorLaunchInfo *)launchInfo
{
  NSParameterAssert(launchInfo);

  // If we have Application-centric Launch Info, deduplicate.
  if (self.launchInfo.simulatorProcess) {
    return;
  }
  // If there's allready launch info and the new info lacks application launch info, deduplicate.
  if (self.launchInfo && !launchInfo.simulatorProcess) {
    return;
  }
  self.launchInfo = launchInfo;
  [self.sink didStartWithLaunchInfo:launchInfo];
}

- (void)didTerminate:(BOOL)expected
{
  // De-duplicate known-terminated Simulators.
  if (!self.launchInfo) {
    return;
  }
  self.launchInfo = nil;
  [self.sink didTerminate:expected];
}

- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)agentProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  // De-duplicate known-launched agents.
  if ([self.knownLaunchedProcesses containsObject:agentProcess]) {
    return;
  }

  [self.knownLaunchedProcesses addObject:agentProcess];
  [self createNotifierForProcess:agentProcess withHandler:^(FBSimulatorEventRelay *relay) {
    [relay agentDidTerminate:agentProcess expected:NO];
  }];
  [self.sink agentDidLaunch:launchConfig didStart:agentProcess stdOut:stdOut stdErr:stdErr];
}

- (void)agentDidTerminate:(FBProcessInfo *)agentProcess expected:(BOOL)expected
{
  if (![self.knownLaunchedProcesses containsObject:agentProcess]) {
    return;
  }

  [self unregisterNotifierForProcess:agentProcess];
  [self.sink agentDidTerminate:agentProcess expected:expected];
}

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  // De-duplicate known-launched applications.
  if ([self.knownLaunchedProcesses containsObject:applicationProcess]) {
    return;
  }

  [self.knownLaunchedProcesses addObject:applicationProcess];
  [self createNotifierForProcess:applicationProcess withHandler:^(FBSimulatorEventRelay *relay) {
    [relay applicationDidTerminate:applicationProcess expected:NO];
  }];
  [self.sink applicationDidLaunch:launchConfig didStart:applicationProcess stdOut:stdOut stdErr:stdErr];
}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  if (![self.knownLaunchedProcesses containsObject:applicationProcess]) {
    return;
  }

  [self.knownLaunchedProcesses removeObject:applicationProcess];
  [self unregisterNotifierForProcess:applicationProcess];
  [self.sink applicationDidTerminate:applicationProcess expected:expected];
}

- (void)diagnosticInformationAvailable:(NSString *)name process:(FBProcessInfo *)process value:(id<NSCopying, NSCoding>)value
{
  [self.sink diagnosticInformationAvailable:name process:process value:value];
}

- (void)didChangeState:(FBSimulatorState)state
{
  if (state == self.lastKnownState) {
    return;
  }
  if (state == FBSimulatorStateBooted) {
    [self fetchLaunchInfoFromBoot];
  }
  if (state != FBSimulatorStateBooted) {
    [self discardLaunchInfoFromBoot];
  }

  self.lastKnownState = state;
  [self.sink didChangeState:state];
}

- (void)terminationHandleAvailable:(id<FBTerminationHandle>)terminationHandle
{
  [self.sink terminationHandleAvailable:terminationHandle];
}

#pragma mark Private

#pragma mark Process Termination

- (void)createNotifierForProcess:(FBProcessInfo *)process withHandler:( void(^)(FBSimulatorEventRelay *relay) )handler
{
  NSParameterAssert(self.processTerminationNotifiers[process] == nil);

  __weak typeof(self) weakSelf = self;
  FBDispatchSourceNotifier *notifier = [FBDispatchSourceNotifier processTerminationNotifierForProcessIdentifier:process.processIdentifier handler:^(FBDispatchSourceNotifier *_) {
    handler(weakSelf);
  }];
  self.processTerminationNotifiers[process] = notifier;
}

- (void)unregisterNotifierForProcess:(FBProcessInfo *)process
{
  FBDispatchSourceNotifier *notifier = self.processTerminationNotifiers[process];
  if (!notifier) {
    return;
  }
  [notifier terminate];
  [self.processTerminationNotifiers removeObjectForKey:process];
}

- (void)unregisterAllNotifiers
{
  [self.processTerminationNotifiers.allValues makeObjectsPerformSelector:@selector(terminate)];
  [self.processTerminationNotifiers removeAllObjects];
  [self.stateChangeNotifier terminate];
  self.stateChangeNotifier = nil;
}

#pragma mark State Notifier

- (void)createNotifierForSimDevice:(SimDevice *)device
{
  __weak typeof(self) weakSelf = self;
  self.stateChangeNotifier = [FBCoreSimulatorNotifier notifierForSimDevice:device block:^(NSDictionary *info) {
    NSNumber *newStateNumber = info[@"new_state"];
    if (!newStateNumber) {
      return;
    }
    [weakSelf didChangeState:newStateNumber.integerValue];
  }];
}

#pragma mark Updating Launch Info from CoreSimulator Notifications

- (void)fetchLaunchInfoFromBoot
{
  // We allready have launch info, possibly superceeded by an Application LaunchInfo variant.
  if (self.launchInfo) {
    return;
  }

  FBSimulatorLaunchInfo *launchInfo = [FBSimulatorLaunchInfo directLaunchOfSimDevice:self.simDevice query:self.processQuery];
  if (!launchInfo) {
    return;
  }
  [self didStartWithLaunchInfo:launchInfo];
}

- (void)discardLaunchInfoFromBoot
{
  // Don't look at the application if we know if we don't consider the Simulator boot.
  if (!self.launchInfo) {
    return;
  }

  // Notify of Simulator Termination.
  [self didTerminate:NO];
}

#pragma mark Simulator Application Launch/Termination

- (void)registerSimulatorLifecycleHandlers
{
  [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(workspaceApplicationDidLaunch:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
  [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(workspaceApplicationDidTerminate:) name:NSWorkspaceDidTerminateApplicationNotification object:nil];
}

- (void)unregisterSimulatorLifecycleHandlers
{
  [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self name:NSWorkspaceDidLaunchApplicationNotification object:nil];
  [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self name:NSWorkspaceDidTerminateApplicationNotification object:nil];
}

- (void)workspaceApplicationDidLaunch:(NSNotification *)notification
{
  // Don't fetch Launch Info for the Application if we an Application corresponding to it.
  // This will superceed any launchInfo information that has been considered a 'Direct Launch'
  // See the FBSimlatorLaunchInfo header for more information about the differences.
  if (self.launchInfo.simulatorProcess) {
    return;
  }

  // The Application must contain the FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID key in the environment
  // This Environment Variable exists to allow interested parties to know the UDID of the Launched Simulator,
  // without having to inspect the Simulator Application's launchd_sim
  NSRunningApplication *launchedApplication = notification.userInfo[NSWorkspaceApplicationKey];
  FBProcessInfo *simulatorProcess =[self.processQuery processInfoFor:launchedApplication.processIdentifier];
  if (![simulatorProcess.environment[FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID] isEqual:self.simDevice.UDID.UUIDString]) {
    return;
  }

  // A timeout is used here as there may be some latency in the Simulator.app launching and the Simulator.app booting the SimDevice.
  // Waiting a reasonable time here prevents the booting of the SimDevice racing with the delivery of NSWorkspaceDidLaunchApplicationNotification.
  FBSimulatorLaunchInfo *launchInfo = [FBSimulatorLaunchInfo launchedViaApplication:launchedApplication ofSimDevice:self.simDevice query:self.processQuery timeout:FBSimulatorControlGlobalConfiguration.regularTimeout];
  if (!launchInfo) {
    return;
  }
  [self didStartWithLaunchInfo:launchInfo];
}

- (void)workspaceApplicationDidTerminate:(NSNotification *)notification
{
  // Don't look at the application if we know if we don't consider the Simulator launched.
  if (!self.launchInfo) {
    return;
  }

  // See if the terminated application is the same as the launch info.
  NSRunningApplication *terminatedApplication = notification.userInfo[NSWorkspaceApplicationKey];
  if (terminatedApplication.processIdentifier != self.launchInfo.simulatorApplication.processIdentifier) {
    return;
  }

  // Notify of Simulator Termination.
  [self didTerminate:NO];
}

@end

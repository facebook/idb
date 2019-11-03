/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorContainerApplicationLifecycleStrategy.h"

#import <AppKit/AppKit.h>
#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorProcessFetcher.h"
#import "FBSimulatorSet.h"

@interface FBSimulatorContainerApplicationLifecycleStrategy ()

@property (nonatomic, weak, readonly) FBSimulatorSet *set;
@property (nonatomic, strong, readonly) NSMapTable<NSNumber *, FBSimulator *> *processToSimulator;

@end

@implementation FBSimulatorContainerApplicationLifecycleStrategy

#pragma mark Initializers

+ (instancetype)strategyForSet:(FBSimulatorSet *)set
{
  FBSimulatorContainerApplicationLifecycleStrategy *strategy = [[self alloc] initWithSet:set];
  [strategy registerHandlers];
  return strategy;
}

- (instancetype)initWithSet:(FBSimulatorSet *)set
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;
  _processToSimulator = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsWeakMemory];

  return self;
}

- (void)dealloc
{
  [self unregisterHandlers];
}

#pragma mark Private

- (FBProcessFetcher *)processFetcher
{
  return self.set.processFetcher.processFetcher;
}

- (void)registerHandlers
{
  [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(workspaceApplicationDidLaunch:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
  [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(workspaceApplicationDidTerminate:) name:NSWorkspaceDidTerminateApplicationNotification object:nil];
}

- (void)unregisterHandlers
{
  [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self name:NSWorkspaceDidLaunchApplicationNotification object:nil];
  [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self name:NSWorkspaceDidTerminateApplicationNotification object:nil];
}

- (void)workspaceApplicationDidLaunch:(NSNotification *)notification
{
  FBProcessInfo *process = nil;
  FBSimulator *simulator = [self simulatorForNotification:notification launchedProcessOut:&process];
  if (!simulator) {
    return;
  }
  [self.processToSimulator setObject:simulator forKey:@(process.processIdentifier)];
  [simulator.eventSink containerApplicationDidLaunch:process];
}

- (void)workspaceApplicationDidTerminate:(NSNotification *)notification
{
  // Don't look at the application if we know if we don't consider the Simulator launched.
  NSRunningApplication *launchedApplication = notification.userInfo[NSWorkspaceApplicationKey];
  FBSimulator *simulator = [self.processToSimulator objectForKey:@(launchedApplication.processIdentifier)];
  if (!simulator) {
    return;
  }

  // See if the terminated application is the same as the launch info.
  FBProcessInfo *container = simulator.containerApplication;
  if (!container) {
    return;
  }

  // Notify of Simulator Termination.
  [simulator.eventSink containerApplicationDidTerminate:container expected:NO];
}

- (FBSimulator *)simulatorForNotification:(NSNotification *)notification launchedProcessOut:(FBProcessInfo **)launchedProcessOut
{
  // Don't fetch Container Application info if we already have it
  NSRunningApplication *launchedApplication = notification.userInfo[NSWorkspaceApplicationKey];
  FBProcessInfo *launchedProcess = [self.processFetcher processInfoFor:launchedApplication.processIdentifier];
  if (!launchedProcess) {
    return nil;
  }

  // The Application must contain the FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID key in the environment
  // This Environment Variable exists to allow interested parties to know the UDID of the Launched Simulator,
  // without having to inspect the Simulator Application's launchd_sim first.
  NSString *udid = launchedProcess.environment[FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID];
  if (!udid) {
    return nil;
  }

  // Find the Simulator for this UDID
  FBiOSTargetQuery *query = [FBiOSTargetQuery udid:udid];
  NSArray<FBSimulator *> *simulators = [self.set query:query];
  if (simulators.count != 1) {
    return nil;
  }
  if (launchedProcessOut) {
    *launchedProcessOut = launchedProcess;
  }
  return simulators.firstObject;
}

@end

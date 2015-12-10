/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulator.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorPool+Private.h"

#import <AppKit/AppKit.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

#import "FBProcessInfo.h"
#import "FBProcessQuery.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorControlStaticConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorLaunchInfo.h"
#import "FBSimulatorLogs.h"
#import "FBSimulatorPool.h"
#import "FBTaskExecutor.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

NSTimeInterval const FBSimulatorDefaultTimeout = 20;

NSString *const FBSimulatorDidLaunchNotification = @"FBSimulatorDidLaunchNotification";
NSString *const FBSimulatorDidTerminateNotification = @"FBSimulatorDidTerminateNotification";

@implementation FBSimulator

#pragma mark Lifecycle

+ (instancetype)fromSimDevice:(SimDevice *)device configuration:(FBSimulatorConfiguration *)configuration pool:(FBSimulatorPool *)pool query:(FBProcessQuery *)query
{
  return [[FBSimulator alloc]
    initWithDevice:device
    configuration:configuration ?: [self inferSimulatorConfigurationFromDevice:device]
    pool:pool
    query:query];
}

+ (FBSimulatorConfiguration *)inferSimulatorConfigurationFromDevice:(SimDevice *)device
{
  return [[FBSimulatorConfiguration.defaultConfiguration withDeviceType:device.deviceType] withRuntime:device.runtime];
}

- (instancetype)initWithDevice:(SimDevice *)device configuration:(FBSimulatorConfiguration *)configuration pool:(FBSimulatorPool *)pool query:(FBProcessQuery *)query
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _configuration = configuration;
  _pool = pool;
  _launchInfo = [FBSimulatorLaunchInfo fromSimDevice:device query:query];
  _processQuery = query;

  [self registerSimulatorLifecycleHandlers];

  return self;
}

- (void)dealloc
{
  [self deregisterSimulatorLifecycleHandlers];
}

#pragma mark Properties

- (NSString *)name
{
  return self.device.name;
}

- (NSString *)udid
{
  return self.device.UDID.UUIDString;
}

- (FBSimulatorState)state
{
  return (NSInteger) self.device.state;
}

- (NSString *)stateString
{
  return [FBSimulator stateStringFromSimulatorState:self.state];
}

- (FBSimulatorApplication *)simulatorApplication
{
  return self.pool.configuration.simulatorApplication;
}

- (NSString *)dataDirectory
{
  return self.device.dataPath;
}

- (BOOL)isAllocated
{
  if (!self.pool) {
    return NO;
  }
  return [self.pool.allocatedSimulators containsObject:self];
}

- (FBSimulatorLogs *)logs
{
  return [FBSimulatorLogs withSimulator:self];
}

#pragma mark Helpers

+ (FBSimulatorState)simulatorStateFromStateString:(NSString *)stateString
{
  stateString = [stateString lowercaseString];
  if ([stateString isEqualToString:@"creating"]) {
    return FBSimulatorStateCreating;
  }
  if ([stateString isEqualToString:@"shutdown"]) {
    return FBSimulatorStateShutdown;
  }
  if ([stateString isEqualToString:@"booting"]) {
    return FBSimulatorStateBooting;
  }
  if ([stateString isEqualToString:@"booted"]) {
    return FBSimulatorStateBooted;
  }
  if ([stateString isEqualToString:@"creating"]) {
    return FBSimulatorStateCreating;
  }
  if ([stateString isEqualToString:@"shutting down"]) {
    return FBSimulatorStateCreating;
  }
  return FBSimulatorStateUnknown;
}

+ (NSString *)stateStringFromSimulatorState:(FBSimulatorState)state
{
  switch (state) {
    case FBSimulatorStateCreating:
      return @"Creating";
    case FBSimulatorStateShutdown:
      return @"Shutdown";
    case FBSimulatorStateBooting:
      return @"Booting";
    case FBSimulatorStateBooted:
      return @"Booted";
    case FBSimulatorStateShuttingDown:
      return @"Shutting Down";
    default:
      return @"Unknown";
  }
}

- (BOOL)waitOnState:(FBSimulatorState)state
{
  return [self waitOnState:state timeout:FBSimulatorDefaultTimeout];
}

- (BOOL)waitOnState:(FBSimulatorState)state timeout:(NSTimeInterval)timeout
{
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^ BOOL {
    return self.state == state;
  }];
}

- (BOOL)waitOnState:(FBSimulatorState)state withError:(NSError **)error
{
  if (![self waitOnState:state]) {
    return [[[FBSimulatorError
      describeFormat:@"Simulator was not in expected %@ state, got %@", [FBSimulator stateStringFromSimulatorState:state], self.stateString]
      inSimulator:self]
      failBool:error];
  }
  return YES;
}

- (BOOL)freeFromPoolWithError:(NSError **)error
{
  if (!self.pool) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot free from pool as there is no pool associated" errorOut:error];
  }
  if (!self.isAllocated) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot free from pool as this Simulator has not been allocated" errorOut:error];
  }
  return [self.pool freeSimulator:self error:error];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.device.hash;
}

- (BOOL)isEqual:(FBSimulator *)simulator
{
  if (![simulator isKindOfClass:self.class]) {
    return NO;
  }
  return [self.device isEqual:simulator.device];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Name %@ | UUID %@ | State %@ | %@",
    self.name,
    self.udid,
    self.device.stateString,
    self.launchInfo
  ];
}

#pragma mark Private

- (void)registerSimulatorLifecycleHandlers
{
  [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(applicationDidTerminate:) name:NSWorkspaceDidTerminateApplicationNotification object:nil];
  [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(applicationDidLaunch:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
}

- (void)deregisterSimulatorLifecycleHandlers
{
  [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self name:NSWorkspaceDidTerminateApplicationNotification object:nil];
  [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self name:NSWorkspaceDidLaunchApplicationNotification object:nil];
}

- (void)applicationDidTerminate:(NSNotification *)notification
{
  if (!self.launchInfo) {
    return;
  }

  NSRunningApplication *terminatedApplication = notification.userInfo[NSWorkspaceApplicationKey];
  if (![terminatedApplication isEqual:self.launchInfo.simulatorApplication]) {
    return;
  }
  [self wasTerminated];
}

- (void)applicationDidLaunch:(NSNotification *)notification
{
  // Don't update the state from a notification if either
  // 1) There is existing launch informatin
  // 2) The Simulator is managed by a session, as the session will update the state by calling `wasLaunchedWithProcessIdentifier`
  if (self.launchInfo || self.session) {
    return;
  }

  NSRunningApplication *launchedApplication = notification.userInfo[NSWorkspaceApplicationKey];
  id<FBProcessInfo> processInfo = [self.processQuery processInfoFor:launchedApplication.processIdentifier];  
  NSString *UDID = processInfo.environment[FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID];
  const BOOL isSimulatorPreparedWithSimCtl = (UDID && [self.udid isEqualToString:UDID]);
  if (!isSimulatorPreparedWithSimCtl) {
    return;
  }

  [self wasLaunchedWithProcessIdentifier:launchedApplication.processIdentifier];
}

- (void)wasLaunchedWithProcessIdentifier:(pid_t)processIdentifier
{
  if (self.launchInfo) {
    return;
  }

  self.launchInfo = [FBSimulatorLaunchInfo fromSimDevice:self.device query:self.processQuery timeout:3];
  if (!self.launchInfo) {
    return;
  }
  [[NSNotificationCenter defaultCenter] postNotificationName:FBSimulatorDidLaunchNotification object:self];
}

- (void)wasTerminated
{
  if (!self.launchInfo) {
    return;
  }
  self.launchInfo = nil;
  [[NSNotificationCenter defaultCenter] postNotificationName:FBSimulatorDidTerminateNotification object:self];
}

@end

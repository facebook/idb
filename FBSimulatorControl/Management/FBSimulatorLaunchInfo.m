/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLaunchInfo.h"

#import <AppKit/AppKit.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

#import "FBProcessInfo.h"
#import "FBProcessQuery.h"
#import "FBProcessQuery+Simulators.h"
#import "FBSimulatorError.h"
#import "FBTaskExecutor.h"

@interface FBSimulatorLaunchInfo ()

@property (nonatomic, strong, readonly) SimDevice *device;
@property (nonatomic, strong, readonly) FBProcessQuery *processQuery;

@property (nonatomic, copy, readwrite) id<FBProcessInfo> simulatorProcess;
@property (nonatomic, copy, readwrite) id<FBProcessInfo> launchdProcess;

@end

@implementation FBSimulatorLaunchInfo

#pragma mark Public

+ (instancetype)fromSimDevice:(SimDevice *)simDevice query:(FBProcessQuery *)query
{
  id<FBProcessInfo> launchdSimProcess = [self launchdSimProcessForUDID:simDevice.UDID.UUIDString query:query];
  if (!launchdSimProcess) {
    return nil;
  }
  id<FBProcessInfo> simulatorProcess = [self simulatorProcessWithUDID:simDevice.UDID.UUIDString query:query];
  if (!simulatorProcess) {
    return nil;
  }
  NSRunningApplication *runningApplication = [self runningApplicationForSimulatorProcess:simulatorProcess query:query];
  if (!runningApplication) {
    return nil;
  }
  return [[FBSimulatorLaunchInfo alloc] initWithDevice:simDevice query:query simulatorProcess:simulatorProcess launchdProcess:launchdSimProcess simulatorApplication:runningApplication];
}

- (instancetype)initWithDevice:(SimDevice *)device query:(FBProcessQuery *)query simulatorProcess:(id<FBProcessInfo>)simulatorProcess launchdProcess:(id<FBProcessInfo>)launchdProcess simulatorApplication:(NSRunningApplication *)simulatorApplication
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _processQuery = query;
  _simulatorProcess = simulatorProcess;
  _launchdProcess = launchdProcess;
  _simulatorApplication = simulatorApplication;

  return self;
}

- (NSArray *)launchedProcesses
{
  return [self.processQuery subprocessesOf:self.launchdProcess.processIdentifier];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"simulator_pid %d | launchd_sim_pid %d",
    self.simulatorProcess.processIdentifier,
    self.launchdProcess.processIdentifier
  ];
}

#pragma mark Private

+ (id<FBProcessInfo>)simulatorProcessWithUDID:(NSString *)udid query:(FBProcessQuery *)query
{
  return [[[query simulatorProcesses]
    filteredArrayUsingPredicate:[FBProcessQuery simulatorProcessesMatchingUDIDs:@[udid]]]
    firstObject];
}

+ (id<FBProcessInfo>)launchdSimProcessForUDID:(NSString *)udid query:(FBProcessQuery *)query
{
  for (id<FBProcessInfo> info in [query processesWithProcessName:@"launchd_sim"]) {
    NSString *udidContainingString = info.environment[@"XPC_SIMULATOR_LAUNCHD_NAME"];
    if ([udidContainingString rangeOfString:udid].location != NSNotFound) {
      return info;
    }
  }
  return nil;
}

+ (NSRunningApplication *)runningApplicationForSimulatorProcess:(id<FBProcessInfo>)process query:(FBProcessQuery *)query
{
  NSRunningApplication *application = [[query
    runningApplicationsForProcesses:@[process]]
    firstObject];

  if (![application isKindOfClass:NSRunningApplication.class]) {
    return nil;
  }

  return application;
}

@end

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
#import "FBProcessQuery+Helpers.h"
#import "FBProcessQuery+Simulators.h"
#import "FBProcessQuery.h"
#import "FBSimulatorError.h"
#import "FBTaskExecutor.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

@interface FBSimulatorLaunchInfo ()

@property (nonatomic, strong, readonly) SimDevice *device;
@property (nonatomic, strong, readonly) FBProcessQuery *processQuery;

@end

@interface FBSimulatorLaunchInfo_ApplicationLaunched : FBSimulatorLaunchInfo

@end

@implementation FBSimulatorLaunchInfo

#pragma mark Public

+ (instancetype)launchedViaApplicationOfSimDevice:(SimDevice *)simDevice query:(FBProcessQuery *)query
{
  FBProcessInfo *launchdSimProcess = [query launchdSimProcessForSimDevice:simDevice];
  if (!launchdSimProcess) {
    return nil;
  }
  FBProcessInfo *simulatorProcess = [query simulatorApplicationProcessForSimDevice:simDevice];
  if (!simulatorProcess) {
    return nil;
  }
  NSRunningApplication *simulatorApplication = [query runningApplicationForProcess:simulatorProcess];
  if (!simulatorApplication) {
    return nil;
  }
  return [[FBSimulatorLaunchInfo_ApplicationLaunched alloc] initWithDevice:simDevice query:query launchdProcess:launchdSimProcess simulatorProcess:simulatorProcess simulatorApplication:simulatorApplication];
}

+ (instancetype)launchedViaApplicationOfSimDevice:(SimDevice *)simDevice query:(FBProcessQuery *)query timeout:(NSTimeInterval)timeout
{
  __block FBSimulatorLaunchInfo *launchInfo = nil;
  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^ BOOL {
    launchInfo = [FBSimulatorLaunchInfo launchedViaApplicationOfSimDevice:simDevice query:query];
    return launchInfo != nil;
  }];
  return launchInfo;
}

+ (instancetype)launchedViaApplication:(SimDevice *)simDevice ofSimDevice:(NSRunningApplication *)simulatorApplication query:(FBProcessQuery *)query timeout:(NSTimeInterval)timeout
{
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilExists:^{
    return [FBSimulatorLaunchInfo launchedViaApplication:simulatorApplication ofSimDevice:simDevice query:query];
  }];
}

+ (instancetype)launchedViaApplication:(SimDevice *)simDevice ofSimDevice:(NSRunningApplication *)simulatorApplication query:(FBProcessQuery *)query
{
  FBProcessInfo *simulatorProcess = [query simulatorApplicationProcessForSimDevice:simDevice];
  if (!simulatorProcess) {
    return nil;
  }
  if (simulatorProcess.processIdentifier != simulatorApplication.processIdentifier) {
    return nil;
  }
  FBProcessInfo *launchdSimProcess = [query launchdSimProcessForSimDevice:simDevice];
  if (!launchdSimProcess) {
    return nil;
  }
  return [[FBSimulatorLaunchInfo_ApplicationLaunched alloc] initWithDevice:simDevice query:query launchdProcess:launchdSimProcess simulatorProcess:simulatorProcess simulatorApplication:simulatorApplication];
}

- (instancetype)initWithDevice:(SimDevice *)device query:(FBProcessQuery *)query launchdProcess:(FBProcessInfo *)launchdProcess
{
  return [self initWithDevice:device query:query launchdProcess:launchdProcess simulatorProcess:nil simulatorApplication:nil];
}

- (instancetype)initWithDevice:(SimDevice *)device query:(FBProcessQuery *)query launchdProcess:(FBProcessInfo *)launchdProcess simulatorProcess:(FBProcessInfo *)simulatorProcess simulatorApplication:(NSRunningApplication *)simulatorApplication
{
  NSParameterAssert(device);
  NSParameterAssert(query);
  NSParameterAssert(launchdProcess);

  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _processQuery = query;
  _launchdProcess = launchdProcess;
  _simulatorProcess = simulatorProcess;
  _simulatorApplication = simulatorApplication;

  return self;
}

- (NSArray *)launchedProcesses
{
  return [self.processQuery subprocessesOf:self.launchdProcess.processIdentifier];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.simulatorApplication.hash ^ self.simulatorProcess.hash | self.launchdProcess.hash;
}

- (BOOL)isEqual:(FBSimulatorLaunchInfo *)info
{
  if (![info isKindOfClass:FBSimulatorLaunchInfo.class]) {
    return NO;
  }

  return [self.launchdProcess isEqual:info.launchdProcess] &&
         (self.simulatorApplication == info.simulatorApplication || [self.simulatorApplication isEqual:info.simulatorApplication]) &&
         (self.simulatorProcess == info.simulatorProcess || [self.simulatorProcess isEqual:info.simulatorProcess]);
}

#pragma mark Descriptions

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"launchd_sim Process (%@)",
    self.launchdProcess.debugDescription
  ];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"launchd_sim_pid %d",
    self.launchdProcess.processIdentifier
  ];
}

- (NSString *)description
{
  return self.debugDescription;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc]
    initWithDevice:self.device
    query:self.processQuery
    launchdProcess:self.launchdProcess
    simulatorProcess:self.simulatorProcess
    simulatorApplication:self.simulatorApplication];
}

@end

@implementation FBSimulatorLaunchInfo_ApplicationLaunched

#pragma mark Descriptions

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"%@ | Simulator Process (%@)",
    [super debugDescription],
    self.simulatorProcess.debugDescription
  ];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"%@ | simulator_pid %d",
    [super shortDescription],
    self.launchdProcess.processIdentifier
  ];
}

@end

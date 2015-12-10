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
#import "FBProcessQuery+Simulators.h"
#import "FBProcessQuery.h"
#import "FBSimulatorError.h"
#import "FBTaskExecutor.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

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
  id<FBProcessInfo> launchdSimProcess = [query launchdSimProcessForSimDevice:simDevice];
  if (!launchdSimProcess) {
    return nil;
  }
  id<FBProcessInfo> simulatorProcess = [query simulatorApplicationProcessForSimDevice:simDevice];
  if (!simulatorProcess) {
    return nil;
  }
  NSRunningApplication *runningApplication = [query runningApplicationForProcess:simulatorProcess];
  if (!runningApplication) {
    return nil;
  }
  return [[FBSimulatorLaunchInfo alloc] initWithDevice:simDevice query:query simulatorProcess:simulatorProcess launchdProcess:launchdSimProcess simulatorApplication:runningApplication];
}

+ (instancetype)fromSimDevice:(SimDevice *)simDevice query:(FBProcessQuery *)query timeout:(NSTimeInterval)timeout
{
  __block FBSimulatorLaunchInfo *launchInfo = nil;
  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    launchInfo = [FBSimulatorLaunchInfo fromSimDevice:simDevice query:query];
    return launchInfo != nil;
  }];
  return launchInfo;
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

- (NSUInteger)hash
{
  return self.simulatorApplication.hash ^ self.simulatorProcess.hash | self.launchdProcess.hash;
}

- (BOOL)isEqual:(FBSimulatorLaunchInfo *)info
{
  if (![info isKindOfClass:FBSimulatorLaunchInfo.class]) {
    return NO;
  }

  return [self.simulatorApplication isEqual:info.simulatorApplication] &&
         [self.simulatorProcess isEqual:info.simulatorProcess] &&
         [self.launchdProcess isEqual:info.launchdProcess];
}

@end

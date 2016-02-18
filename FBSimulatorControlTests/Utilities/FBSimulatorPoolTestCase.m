/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorPoolTestCase.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "CoreSimulatorDoubles.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorPool.h"

@interface FBSimulatorPoolTestCase ()

@end

@implementation FBSimulatorPoolTestCase

- (void)teardown
{
  _pool = nil;
}

- (NSArray *)createPoolWithExistingSimDeviceSpecs:(NSArray *)simulatorSpecs
{
  NSMutableArray *simulators = [NSMutableArray array];
  for (NSDictionary *simulatorSpec in simulatorSpecs) {
    NSString *name = simulatorSpec[@"name"];
    NSUUID *uuid = simulatorSpec[@"uuid"] ?: [NSUUID UUID];
    NSString *os = simulatorSpec[@"os"] ?: @"iOS 9.0";
    NSString *version = [[os componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lastObject];
    FBSimulatorState state = [(simulatorSpec[@"state"] ?: @(FBSimulatorStateShutdown)) integerValue];

    FBSimulatorControlTests_SimDeviceType_Double *deviceType = [FBSimulatorControlTests_SimDeviceType_Double new];
    deviceType.name = name;

    FBSimulatorControlTests_SimDeviceRuntime_Double *runtime = [FBSimulatorControlTests_SimDeviceRuntime_Double new];
    runtime.name = os;
    runtime.versionString = version;

    FBSimulatorControlTests_SimDevice_Double *device = [FBSimulatorControlTests_SimDevice_Double new];
    device.name = name;
    device.UDID = uuid;
    device.state = (unsigned long long) state;
    device.deviceType = deviceType;
    device.runtime = runtime;

    [simulators addObject:device];
  }

  FBSimulatorControlTests_SimDeviceSet_Double *deviceSet = [FBSimulatorControlTests_SimDeviceSet_Double new];
  deviceSet.availableDevices = [simulators copy];

  FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration configurationWithDeviceSetPath:nil options:0];
  _set = [[FBSimulatorSet alloc] initWithConfiguration:configuration deviceSet:(id)deviceSet logger:nil];
  _pool = [[FBSimulatorPool alloc] initWithSet:_set logger:nil];

  return deviceSet.availableDevices;
}

- (void)mockAllocationOfSimulatorsUDIDs:(NSArray *)deviceUDIDs
{
  NSDictionary *simulatorsByUDID = [NSDictionary dictionaryWithObjects:self.set.allSimulators forKeys:[self.set.allSimulators valueForKey:@"udid"]];
  for (NSUUID *udid in deviceUDIDs) {
    [self.pool.allocatedUDIDs addObject:udid.UUIDString];
    [simulatorsByUDID[udid.UUIDString] setPool:self.pool];
  }
}

@end

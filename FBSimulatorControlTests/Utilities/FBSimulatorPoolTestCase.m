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

@interface FBSimulatorPoolTestCase ()

@end

@implementation FBSimulatorPoolTestCase

- (void)teardown
{
  _pool = nil;
}

- (NSArray<FBSimulator *> *)createPoolWithExistingSimDeviceSpecs:(NSArray<NSDictionary<NSString *, id> *> *)simulatorSpecs
{
  NSMutableArray<SimDevice *> *simDevices = [NSMutableArray array];
  for (NSDictionary<NSString *, id> *simulatorSpec in simulatorSpecs) {
    FBDeviceModel name = simulatorSpec[@"name"];
    NSUUID *uuid = simulatorSpec[@"uuid"] ?: [NSUUID UUID];
    FBOSVersionName os = simulatorSpec[@"os"] ?: FBOSVersionNameiOS_9_0;
    NSString *version = [[os componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lastObject];
    FBSimulatorState state = [(simulatorSpec[@"state"] ?: @(FBSimulatorStateShutdown)) unsignedIntegerValue];

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

    [simDevices addObject:(SimDevice *)device];
  }

  FBSimulatorControlTests_SimDeviceSet_Double *deviceSet = [FBSimulatorControlTests_SimDeviceSet_Double new];
  deviceSet.availableDevices = [simDevices copy];

  FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration configurationWithDeviceSetPath:nil options:0];
  _set = [[FBSimulatorSet alloc] initWithConfiguration:configuration deviceSet:(id)deviceSet logger:nil];
  _pool = [[FBSimulatorPool alloc] initWithSet:_set logger:nil];

  NSArray<FBSimulator *> *simulators = _set.allSimulators;
  XCTAssertEqual(simulators.count, simDevices.count);

  // Also confirm that the input ordering is the same as the output ordering
  for (NSUInteger index = 0; index < simulators.count; index++) {
    FBDeviceModel expected = simulatorSpecs[index][@"name"];
    FBDeviceModel actual = simulators[index].deviceType.model;
    XCTAssertEqualObjects(expected, actual);
  }

  return simulators;
}

- (void)mockAllocationOfSimulatorsUDIDs:(NSArray<NSString *> *)deviceUDIDs
{
  NSDictionary<NSString *, FBSimulator *> *simulatorsByUDID = [NSDictionary dictionaryWithObjects:self.set.allSimulators forKeys:[self.set.allSimulators valueForKey:@"udid"]];
  for (NSString *udid in deviceUDIDs) {
    [self.pool.allocatedUDIDs addObject:udid];
    [simulatorsByUDID[udid] setPool:self.pool];
  }
}

@end

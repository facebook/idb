/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorSetTestCase.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "CoreSimulatorDoubles.h"
#import "FBSimulatorControlFixtures.h"

@interface FBSimulatorSetTestCase ()

@end

@implementation FBSimulatorSetTestCase

- (NSArray<FBSimulator *> *)createSetWithExistingSimDeviceSpecs:(NSArray<NSDictionary<NSString *, id> *> *)simulatorSpecs
{
  NSMutableArray<SimDevice *> *simDevices = [NSMutableArray array];
  for (NSDictionary<NSString *, id> *simulatorSpec in simulatorSpecs) {
    FBDeviceModel name = simulatorSpec[@"name"];
    NSUUID *uuid = simulatorSpec[@"uuid"] ?: [NSUUID UUID];
    FBOSVersionName os = simulatorSpec[@"os"] ?: FBOSVersionNameiOS_9_0;
    NSString *version = [[os componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lastObject];
    FBiOSTargetState state = [(simulatorSpec[@"state"] ?: @(FBiOSTargetStateShutdown)) unsignedIntegerValue];

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

  FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration configurationWithDeviceSetPath:nil options:0 logger:nil reporter:nil];
  _set = [FBSimulatorSet setWithConfiguration:configuration deviceSet:(id)deviceSet delegate:nil logger:nil reporter:nil error:nil];

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

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "CoreSimulatorDoubles.h"
#import "FBSimulatorPoolTestCase.h"

@interface FBSimulatorSetTests : FBSimulatorPoolTestCase

@end

@implementation FBSimulatorSetTests

- (void)testInflatesSimulators
{
  [self createPoolWithExistingSimDeviceSpecs:@[
    @{@"name" : FBDeviceModeliPhone5, @"state" : @(FBSimulatorStateCreating)},
    @{@"name" : FBDeviceModeliPhone5, @"state" : @(FBSimulatorStateShutdown)},
    @{@"name" : FBDeviceModeliPhone5, @"state" : @(FBSimulatorStateBooted)},
    @{@"name" : FBDeviceModeliPhone6S, @"state" : @(FBSimulatorStateShuttingDown)},
    @{@"name" : FBDeviceModeliPad2, @"state" : @(FBSimulatorStateBooted)},
    @{@"name" : FBDeviceModeliPadAir, @"state" : @(FBSimulatorStateBooted)},
    @{@"name" : FBDeviceModeliPadAir2, @"state" : @(FBSimulatorStateCreating)},
    @{@"name" : FBDeviceModeliPhone5, @"state" : @(FBSimulatorStateShutdown), @"os" : FBOSVersionNameiOS_10_0},
  ]];

  NSArray<FBSimulator *> *simulators = self.set.allSimulators;
  XCTAssertEqual(simulators.count, 8u);

  FBSimulator *simulator = simulators[0];
  XCTAssertEqualObjects(simulator.name, FBDeviceModeliPhone5);
  XCTAssertEqual(simulator.state, FBSimulatorStateCreating);
  XCTAssertEqual(simulator.set, self.set);

  simulator = simulators[1];
  XCTAssertEqualObjects(simulator.name, FBDeviceModeliPhone5);
  XCTAssertEqual(simulator.state, FBSimulatorStateShutdown);
  XCTAssertEqual(simulator.set, self.set);

  simulator = simulators[2];
  XCTAssertEqualObjects(simulator.name, FBDeviceModeliPhone5);
  XCTAssertEqual(simulator.state, FBSimulatorStateBooted);
  XCTAssertEqual(simulator.set, self.set);

  simulator = simulators[3];
  XCTAssertEqualObjects(simulator.name, FBDeviceModeliPhone6S);
  XCTAssertEqual(simulator.state, FBSimulatorStateShuttingDown);
  XCTAssertEqual(simulator.set, self.set);

  simulator = simulators[4];
  XCTAssertEqualObjects(simulator.name, FBDeviceModeliPad2);
  XCTAssertEqual(simulator.state, FBSimulatorStateBooted);
  XCTAssertEqual(simulator.set, self.set);

  simulator = simulators[5];
  XCTAssertEqualObjects(simulator.name, FBDeviceModeliPadAir);
  XCTAssertEqual(simulator.state, FBSimulatorStateBooted);
  XCTAssertEqual(simulator.set, self.set);

  simulator = simulators[6];
  XCTAssertEqualObjects(simulator.name, FBDeviceModeliPadAir2);
  XCTAssertEqual(simulator.state, FBSimulatorStateCreating);
  XCTAssertEqual(simulator.set, self.set);

  simulator = simulators[7];
  XCTAssertEqualObjects(simulator.name, FBDeviceModeliPhone5);
  XCTAssertEqual(simulator.state, FBSimulatorStateShutdown);
  XCTAssertEqual(simulator.set, self.set);
}

- (void)testReferencesForSimulatorsAreTheSame
{
  [self createPoolWithExistingSimDeviceSpecs:@[
    @{@"name" : FBDeviceModeliPhone5, @"state" : @(FBSimulatorStateCreating)},
    @{@"name" : FBDeviceModeliPhone5, @"state" : @(FBSimulatorStateShutdown)},
    @{@"name" : FBDeviceModeliPhone5, @"state" : @(FBSimulatorStateBooted)},
    @{@"name" : FBDeviceModeliPhone6S, @"state" : @(FBSimulatorStateShuttingDown)},
    @{@"name" : FBDeviceModeliPad2, @"state" : @(FBSimulatorStateBooted)},
    @{@"name" : FBDeviceModeliPadAir, @"state" : @(FBSimulatorStateBooted)},
    @{@"name" : FBDeviceModeliPadAir2, @"state" : @(FBSimulatorStateCreating)},
    @{@"name" : FBDeviceModeliPhone5, @"state" : @(FBSimulatorStateShutdown), @"os" : FBOSVersionNameiOS_10_0},
  ]];

  NSArray *firstFetch = self.set.allSimulators;
  NSArray *secondFetch = self.set.allSimulators;
  XCTAssertEqualObjects(firstFetch, secondFetch);

  // Reference equality.
  for (NSUInteger index = 0; index < firstFetch.count; index++) {
    XCTAssertEqual(firstFetch[index], secondFetch[index]);
  }
}

@end

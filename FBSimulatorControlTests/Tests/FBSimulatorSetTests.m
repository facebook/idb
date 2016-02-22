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
    @{@"name" : @"iPad 2", @"state" : @(FBSimulatorStateBooted)},
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateCreating)},
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateShutdown)},
    @{@"name" : @"iPad 3", @"state" : @(FBSimulatorStateCreating)},
    @{@"name" : @"iPhone 6S", @"state" : @(FBSimulatorStateShuttingDown) },
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateBooted)},
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateShutdown)},
    @{@"name" : @"iPad", @"state" : @(FBSimulatorStateBooted)}
  ]];

  NSArray *simulators = self.set.allSimulators;
  XCTAssertEqual(simulators.count, 8u);

  FBSimulator *simulator = simulators[0];
  XCTAssertEqualObjects(simulator.name, @"iPad 2");
  XCTAssertEqual(simulator.state, FBSimulatorStateBooted);
  XCTAssertEqual(simulator.set, self.set);

  simulator = simulators[1];
  XCTAssertEqualObjects(simulator.name, @"iPhone 5");
  XCTAssertEqual(simulator.state, FBSimulatorStateCreating);
  XCTAssertEqual(simulator.set, self.set);

  simulator = simulators[2];
  XCTAssertEqualObjects(simulator.name, @"iPhone 5");
  XCTAssertEqual(simulator.state, FBSimulatorStateShutdown);
  XCTAssertEqual(simulator.set, self.set);

  simulator = simulators[3];
  XCTAssertEqualObjects(simulator.name, @"iPad 3");
  XCTAssertEqual(simulator.state, FBSimulatorStateCreating);
  XCTAssertEqual(simulator.set, self.set);

  simulator = simulators[4];
  XCTAssertEqualObjects(simulator.name, @"iPhone 6S");
  XCTAssertEqual(simulator.state, FBSimulatorStateShuttingDown);
  XCTAssertEqual(simulator.set, self.set);

  simulator = simulators[5];
  XCTAssertEqualObjects(simulator.name, @"iPhone 5");
  XCTAssertEqual(simulator.state, FBSimulatorStateBooted);
  XCTAssertEqual(simulator.set, self.set);

  simulator = simulators[6];
  XCTAssertEqualObjects(simulator.name, @"iPhone 5");
  XCTAssertEqual(simulator.state, FBSimulatorStateShutdown);
  XCTAssertEqual(simulator.set, self.set);

  simulator = simulators[7];
  XCTAssertEqualObjects(simulator.name, @"iPad");
  XCTAssertEqual(simulator.state, FBSimulatorStateBooted);
  XCTAssertEqual(simulator.set, self.set);
}

- (void)testReferencesForSimulatorsAreTheSame
{
  [self createPoolWithExistingSimDeviceSpecs:@[
    @{@"name" : @"iPad 2", @"state" : @(FBSimulatorStateBooted)},
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateCreating)},
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateShutdown)},
    @{@"name" : @"iPad 3", @"state" : @(FBSimulatorStateCreating)},
    @{@"name" : @"iPhone 6S", @"state" : @(FBSimulatorStateShuttingDown) },
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateBooted)},
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateShutdown)},
    @{@"name" : @"iPad", @"state" : @(FBSimulatorStateBooted)}
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

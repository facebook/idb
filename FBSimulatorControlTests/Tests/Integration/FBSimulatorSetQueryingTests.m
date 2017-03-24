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

#import "FBSimulatorControlAssertions.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorPoolTestCase.h"

@interface FBSimulatorSetQueryingTests : FBSimulatorPoolTestCase

@property (nonatomic, copy, readwrite) NSArray<FBSimulator *> *simulators;

@end

@implementation FBSimulatorSetQueryingTests

- (void)setUp
{
  // Assumes that the orderding of the input is the same as the ordering as -[FBSimulatorSet allSimulators]
  self.simulators = [self createPoolWithExistingSimDeviceSpecs:@[
    @{@"name" : FBDeviceModeliPhone5, @"state" : @(FBSimulatorStateCreating), @"os" : FBOSVersionNameiOS_8_0},
    @{@"name" : FBDeviceModeliPad2, @"state" : @(FBSimulatorStateBooted), @"os" : FBOSVersionNameiOS_8_0},
    @{@"name" : FBDeviceModeliPhone5, @"state" : @(FBSimulatorStateShutdown), @"os" : FBOSVersionNameiOS_9_0},
    @{@"name" : FBDeviceModeliPhone6S, @"state" : @(FBSimulatorStateShuttingDown), @"os" : FBOSVersionNameiOS_9_0},
    @{@"name" : FBDeviceModeliPhone5, @"state" : @(FBSimulatorStateBooted), @"os" : FBOSVersionNameiOS_9_1},
    @{@"name" : FBDeviceModeliPadAir2, @"state" : @(FBSimulatorStateCreating), @"os" : FBOSVersionNameiOS_9_1},
    @{@"name" : FBDeviceModeliPhone5, @"state" : @(FBSimulatorStateShutdown), @"os" : FBOSVersionNameiOS_9_2},
    @{@"name" : FBDeviceModeliPadAir, @"state" : @(FBSimulatorStateBooted), @"os" : FBOSVersionNameiOS_9_3},
  ]];
}

- (void)testFilterBySingleDevice
{
  FBiOSTargetQuery *query = [FBiOSTargetQuery devices:@[FBDeviceModeliPhone5]];
  NSArray<FBSimulator *> *actual = [self.set query:query];
  NSArray<FBSimulator *> *expected = @[self.simulators[0], self.simulators[2], self.simulators[4], self.simulators[6]];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testFilterByMultipleDevices
{
  FBiOSTargetQuery *query = [FBiOSTargetQuery devices:@[FBDeviceModeliPadAir, FBDeviceModeliPadAir2]];
  NSArray<FBSimulator *> *actual = [self.set query:query];
  NSArray<FBSimulator *> *expected = @[self.simulators[5], self.simulators[7]];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testFilterBySingleOSVersion
{
  FBiOSTargetQuery *query = [FBiOSTargetQuery osVersions:@[FBOSVersionNameiOS_9_1]];
  NSArray<FBSimulator *> *actual = [self.set query:query];
  NSArray<FBSimulator *> *expected = @[self.simulators[4], self.simulators[5]];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testFilterByMulitpleOSVersions
{
  FBiOSTargetQuery *query = [FBiOSTargetQuery osVersions:@[FBOSVersionNameiOS_9_2, FBOSVersionNameiOS_9_3]];
  NSArray<FBSimulator *> *actual = [self.set query:query];
  NSArray<FBSimulator *> *expected = @[self.simulators[6], self.simulators[7]];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testFilterBySingleState
{
  FBiOSTargetQuery *query = [FBiOSTargetQuery states:[NSIndexSet indexSetWithIndex:FBSimulatorStateBooted]];
  NSArray<FBSimulator *> *actual = [self.set query:query];
  NSArray<FBSimulator *> *expected = @[self.simulators[1], self.simulators[4], self.simulators[7]];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testFilterBySingleMultipleStates
{
  NSIndexSet *states = [FBCollectionOperations indecesFromArray:@[@(FBSimulatorStateShutdown), @(FBSimulatorStateShuttingDown)]];
  FBiOSTargetQuery *query = [FBiOSTargetQuery states:states];
  NSArray<FBSimulator *> *actual = [self.set query:query];
  NSArray<FBSimulator *> *expected = @[self.simulators[2], self.simulators[3], self.simulators[6]];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testFilterByStateAndName
{
  FBiOSTargetQuery *query = [[FBiOSTargetQuery states:[NSIndexSet indexSetWithIndex:FBSimulatorStateCreating]] devices:@[FBDeviceModeliPhone5]];
  NSArray<FBSimulator *> *actual = [self.set query:query];
  NSArray<FBSimulator *> *expected = @[self.simulators[0]];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testNoMatches
{
  FBiOSTargetQuery *query = [[FBiOSTargetQuery states:[NSIndexSet indexSetWithIndex:FBSimulatorStateBooting]] devices:@[FBDeviceModeliPhone5]];
  NSArray<FBSimulator *> *actual = [self.set query:query];
  NSArray<FBSimulator *> *expected = @[];
  XCTAssertEqualObjects(expected, actual);
}

@end

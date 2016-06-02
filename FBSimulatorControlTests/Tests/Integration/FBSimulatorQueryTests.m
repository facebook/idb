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

@interface FBSimulatorQueryTests : FBSimulatorPoolTestCase

@property (nonatomic, copy, readwrite) NSArray<FBSimulator *> *simulators;

@end

@implementation FBSimulatorQueryTests

- (void)setUp
{
  self.simulators = [self createPoolWithExistingSimDeviceSpecs:@[
    @{@"name" : @"iPad 2", @"state" : @(FBSimulatorStateBooted), @"os" : @"iOS 8.0"},
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateCreating), @"os" : @"iOS 8.0"},
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateShutdown), @"os" : @"iOS 9.0"},
    @{@"name" : @"iPad Air 2", @"state" : @(FBSimulatorStateCreating), @"os" : @"iOS 9.1"},
    @{@"name" : @"iPhone 6S", @"state" : @(FBSimulatorStateShuttingDown), @"os" : @"iOS 9.0"},
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateBooted), @"os" : @"iOS 9.1"},
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateShutdown), @"os" : @"iOS 9.2"},
    @{@"name" : @"iPad Air", @"state" : @(FBSimulatorStateBooted), @"os" : @"iOS 9.3"},
  ]];
}

- (void)testFilterBySingleDevice
{
  FBSimulatorQuery *query = [FBSimulatorQuery devices:@[FBControlCoreConfiguration_Device_iPhone5.new]];
  NSArray<FBSimulator *> *actual = [query perform:self.set];
  NSArray<FBSimulator *> *expected = @[self.simulators[1], self.simulators[2], self.simulators[5], self.simulators[6]];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testFilterByMultipleDevices
{
  FBSimulatorQuery *query = [FBSimulatorQuery devices:@[FBControlCoreConfiguration_Device_iPadAir.new, FBControlCoreConfiguration_Device_iPadAir2.new]];
  NSArray<FBSimulator *> *actual = [query perform:self.set];
  NSArray<FBSimulator *> *expected = @[self.simulators[3], self.simulators[7]];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testFilterBySingleOSVersion
{
  FBSimulatorQuery *query = [FBSimulatorQuery osVersions:@[FBControlCoreConfiguration_iOS_9_1.new]];
  NSArray<FBSimulator *> *actual = [query perform:self.set];
  NSArray<FBSimulator *> *expected = @[self.simulators[3], self.simulators[5]];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testFilterByMulitpleOSVersions
{
  FBSimulatorQuery *query = [FBSimulatorQuery osVersions:@[FBControlCoreConfiguration_iOS_9_2.new, FBControlCoreConfiguration_iOS_9_3.new]];
  NSArray<FBSimulator *> *actual = [query perform:self.set];
  NSArray<FBSimulator *> *expected = @[self.simulators[6], self.simulators[7]];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testFilterBySingleState
{
  FBSimulatorQuery *query = [FBSimulatorQuery states:[NSIndexSet indexSetWithIndex:FBSimulatorStateBooted]];
  NSArray<FBSimulator *> *actual = [query perform:self.set];
  NSArray<FBSimulator *> *expected = @[self.simulators[0], self.simulators[5], self.simulators[7]];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testFilterBySingleMultipleStates
{
  NSIndexSet *states = [FBCollectionOperations indecesFromArray:@[@(FBSimulatorStateShutdown), @(FBSimulatorStateShuttingDown)]];
  FBSimulatorQuery *query = [FBSimulatorQuery states:states];
  NSArray<FBSimulator *> *actual = [query perform:self.set];
  NSArray<FBSimulator *> *expected = @[self.simulators[2], self.simulators[4], self.simulators[6]];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testFilterByStateAndName
{
  FBSimulatorQuery *query = [[FBSimulatorQuery states:[NSIndexSet indexSetWithIndex:FBSimulatorStateCreating]] devices:@[FBControlCoreConfiguration_Device_iPhone5.new]];
  NSArray<FBSimulator *> *actual = [query perform:self.set];
  NSArray<FBSimulator *> *expected = @[self.simulators[1]];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testNoMatches
{
  FBSimulatorQuery *query = [[FBSimulatorQuery states:[NSIndexSet indexSetWithIndex:FBSimulatorStateBooting]] devices:@[FBControlCoreConfiguration_Device_iPhone5.new]];
  NSArray<FBSimulator *> *actual = [query perform:self.set];
  NSArray<FBSimulator *> *expected = @[];
  XCTAssertEqualObjects(expected, actual);
}

@end

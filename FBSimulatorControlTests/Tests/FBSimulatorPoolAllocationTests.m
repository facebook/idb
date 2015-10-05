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
#import <FBSimulatorControl/FBSimulatorControl+Private.h>
#import <FBSimulatorControl/FBSimulatorPool.h>
#import <FBSimulatorControl/FBSimulatorPool+Private.h>
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorApplication.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorConfiguration.h>

#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorPoolAllocationTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorPoolAllocationTests

- (FBSimulatorManagementOptions)managementOptions
{
  return FBSimulatorManagementOptionsDeleteOnFree;
}

- (void)testReallocatesAndErasesFreedDevice
{
  FBSimulatorControlConfiguration *controlConfiguration = [FBSimulatorControlConfiguration
    configurationWithSimulatorApplication:[FBSimulatorApplication simulatorApplicationWithError:nil]
    deviceSetPath:nil
    namePrefix:nil
    bucket:0
    options:FBSimulatorManagementOptionsEraseOnFree];

  FBSimulatorControl *control = [[FBSimulatorControl alloc] initWithConfiguration:controlConfiguration];

  NSError *error = nil;
  FBSimulatorConfiguration *simulatorConfiguration = FBSimulatorConfiguration.iPhone5;
  FBManagedSimulator *simulator = [control.simulatorPool allocateSimulatorWithConfiguration:simulatorConfiguration error:&error];
  XCTAssertNotNil(simulator);
  XCTAssertNil(error);

  NSString *simulatorUUID = simulator.udid;
  [self addTemporaryFileToSimulator:simulator];

  XCTAssertTrue([control.simulatorPool freeSimulator:simulator error:nil]);
  XCTAssertNil(error);

  simulator = [control.simulatorPool allocateSimulatorWithConfiguration:simulatorConfiguration error:&error];
  XCTAssertNotNil(simulator);
  XCTAssertNil(error);
  XCTAssertEqualObjects(simulatorUUID, simulator.udid);
  [self assertTemporaryFileForSimulator:simulator exists:NO];

  XCTAssertTrue([control.simulatorPool freeSimulator:simulator error:nil]);
  XCTAssertNil(error);
}

- (void)testDoesNotReallocateDeletedDevice
{
  NSError *error = nil;
  FBSimulatorConfiguration *simulatorConfiguration = FBSimulatorConfiguration.iPhone5;
  FBManagedSimulator *simulator = [self.control.simulatorPool allocateSimulatorWithConfiguration:simulatorConfiguration error:&error];
  XCTAssertNotNil(simulator);
  XCTAssertNil(error);

  NSString *simulatorUUID = simulator.udid;

  XCTAssertTrue([self.control.simulatorPool freeSimulator:simulator error:nil]);
  XCTAssertNil(error);

  simulator = [self.control.simulatorPool allocateSimulatorWithConfiguration:simulatorConfiguration error:&error];
  XCTAssertNotNil(simulator);
  XCTAssertNil(error);
  XCTAssertNotEqualObjects(simulatorUUID, simulator.udid);

  XCTAssertTrue([self.control.simulatorPool freeSimulator:simulator error:nil]);
  XCTAssertNil(error);
}

- (void)testRemovesDeletedDeviceFromSet
{
  NSError *error = nil;
  FBSimulatorConfiguration *simulatorConfiguration = FBSimulatorConfiguration.iPhone5;
  FBManagedSimulator *simulator = [self.control.simulatorPool allocateSimulatorWithConfiguration:simulatorConfiguration error:&error];
  XCTAssertNotNil(simulator);
  XCTAssertNil(error);

  NSString *simulatorUUID = simulator.udid;

  XCTAssertTrue([self.control.simulatorPool freeSimulator:simulator error:nil]);
  XCTAssertNil(error);

  NSOrderedSet *uuidSet = [self.control.simulatorPool.allPooledSimulators valueForKey:@"udid"];
  XCTAssertFalse([uuidSet containsObject:simulatorUUID]);
}

- (void)testRemovesMultipleAllocatedDevicesFromSet
{
  NSError *error = nil;
  FBSimulatorConfiguration *simulatorConfiguration = FBSimulatorConfiguration.iPhone5;
  NSMutableArray *simulators = [NSMutableArray array];
  NSMutableSet *simulatorUUIDs = [NSMutableSet set];

  for (NSInteger index = 0; index < 4; index++) {
    FBSimulator *simulator = [self.control.simulatorPool allocateSimulatorWithConfiguration:simulatorConfiguration error:&error];
    XCTAssertNotNil(simulator);
    XCTAssertNil(error);
    [simulators addObject:simulator];
    [simulatorUUIDs addObject:simulator.udid];
  }

  XCTAssertTrue([self.control.simulatorPool deleteManagedSimulatorsWithError:&error]);
  XCTAssertNil(error);

  NSOrderedSet *uuidSet = [self.control.simulatorPool.allPooledSimulators valueForKey:@"udid"];
  [simulatorUUIDs intersectSet:uuidSet.set];
  XCTAssertEqual(simulatorUUIDs.count, 0);
}

#pragma mark Helpers

- (NSString *)temporaryFilePathForSimulator:(FBSimulator *)simulator
{
  return [[simulator.dataDirectory stringByAppendingPathComponent:@"something_temp"] stringByAppendingPathExtension:@"txt"];
}

- (void)addTemporaryFileToSimulator:(FBSimulator *)simulator
{
  XCTAssertTrue([@"Hi there I'm a file" writeToFile:[self temporaryFilePathForSimulator:simulator] atomically:YES encoding:NSUTF8StringEncoding error:nil]);
}

- (void)assertTemporaryFileForSimulator:(FBSimulator *)simulator exists:(BOOL)exists
{
  XCTAssertEqual([NSFileManager.defaultManager fileExistsAtPath:[self temporaryFilePathForSimulator:simulator]], exists);
}

@end

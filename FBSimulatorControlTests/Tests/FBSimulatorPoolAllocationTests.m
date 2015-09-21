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
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorApplication.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorConfiguration.h>

@interface FBSimulatorPoolAllocationTests : XCTestCase

@end

@implementation FBSimulatorPoolAllocationTests

#pragma mark Tests

- (void)testReallocatesAndErasesFreedDevice
{
  FBSimulatorControlConfiguration *controlConfiguration = [FBSimulatorControlConfiguration
    configurationWithSimulatorApplication:[FBSimulatorApplication simulatorApplicationWithError:nil]
    bucket:0
    options:FBSimulatorManagementOptionsEraseOnFree];

  FBSimulatorControl *control = [[FBSimulatorControl alloc] initWithConfiguration:controlConfiguration];

  NSError *error = nil;
  FBSimulatorConfiguration *simulatorConfiguration = FBSimulatorConfiguration.iPhone5;
  FBSimulator *simulator = [control.simulatorPool allocateSimulatorWithConfiguration:simulatorConfiguration error:&error];
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
  FBSimulatorControlConfiguration *controlConfiguration = [FBSimulatorControlConfiguration
    configurationWithSimulatorApplication:[FBSimulatorApplication simulatorApplicationWithError:nil]
    bucket:0
    options:FBSimulatorManagementOptionsDeleteOnFree];

  FBSimulatorControl *control = [[FBSimulatorControl alloc] initWithConfiguration:controlConfiguration];

  NSError *error = nil;
  FBSimulatorConfiguration *simulatorConfiguration = FBSimulatorConfiguration.iPhone5;
  FBSimulator *simulator = [control.simulatorPool allocateSimulatorWithConfiguration:simulatorConfiguration error:&error];
  XCTAssertNotNil(simulator);
  XCTAssertNil(error);

  NSString *simulatorUUID = simulator.udid;

  XCTAssertTrue([control.simulatorPool freeSimulator:simulator error:nil]);
  XCTAssertNil(error);

  simulator = [control.simulatorPool allocateSimulatorWithConfiguration:simulatorConfiguration error:&error];
  XCTAssertNotNil(simulator);
  XCTAssertNil(error);
  XCTAssertNotEqualObjects(simulatorUUID, simulator.udid);

  XCTAssertTrue([control.simulatorPool freeSimulator:simulator error:nil]);
  XCTAssertNil(error);
}

- (void)testRemovesDeletedDeviceFromSet
{
  FBSimulatorControlConfiguration *controlConfiguration = [FBSimulatorControlConfiguration
    configurationWithSimulatorApplication:[FBSimulatorApplication simulatorApplicationWithError:nil]
    bucket:0
    options:FBSimulatorManagementOptionsDeleteOnFree];

  FBSimulatorControl *control = [[FBSimulatorControl alloc] initWithConfiguration:controlConfiguration];

  NSError *error = nil;
  FBSimulatorConfiguration *simulatorConfiguration = FBSimulatorConfiguration.iPhone5;
  FBSimulator *simulator = [control.simulatorPool allocateSimulatorWithConfiguration:simulatorConfiguration error:&error];
  XCTAssertNotNil(simulator);
  XCTAssertNil(error);

  NSString *simulatorUUID = simulator.udid;

  XCTAssertTrue([control.simulatorPool freeSimulator:simulator error:nil]);
  XCTAssertNil(error);

  NSOrderedSet *uuidSet = [control.simulatorPool.allPooledSimulators valueForKey:@"udid"];
  XCTAssertFalse([uuidSet containsObject:simulatorUUID]);
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

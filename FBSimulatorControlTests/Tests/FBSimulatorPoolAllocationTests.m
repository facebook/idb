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
#import <FBSimulatorControl/FBSimulatorSession.h>

#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorPoolAllocationTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorPoolAllocationTests

- (void)setUp
{
  NSError *error = nil;
  [NSFileManager.defaultManager removeItemAtPath:self.deviceSetPath error:&error];
  (void)error;

  [super setUp];
}

- (FBSimulatorManagementOptions)managementOptions
{
  return FBSimulatorManagementOptionsDeleteOnFree | FBSimulatorManagementOptionsDeleteAllOnFirstStart;
}

- (NSString *)deviceSetPath
{
  return [NSTemporaryDirectory()
    stringByAppendingPathComponent:[NSString stringWithFormat:@"%@", NSStringFromClass(self.class)]];
}

- (void)testReallocatesAndErasesFreedDevice
{
  FBSimulatorControlConfiguration *controlConfiguration = [FBSimulatorControlConfiguration
    configurationWithSimulatorApplication:[FBSimulatorApplication simulatorApplicationWithError:nil]
    deviceSetPath:self.deviceSetPath
    options:FBSimulatorManagementOptionsEraseOnFree | FBSimulatorManagementOptionsDeleteAllOnFirstStart];

  FBSimulatorControl *control = [[FBSimulatorControl alloc] initWithConfiguration:controlConfiguration];

  NSError *error = nil;
  FBSimulatorConfiguration *simulatorConfiguration = FBSimulatorConfiguration.iPhone5;
  FBSimulator *simulator = [control createSessionForSimulatorConfiguration:simulatorConfiguration error:&error].simulator;
  XCTAssertNotNil(simulator);
  XCTAssertNil(error);

  NSString *simulatorUUID = simulator.udid;
  [self addTemporaryFileToSimulator:simulator];

  XCTAssertTrue([control.simulatorPool freeSimulator:simulator error:nil]);
  XCTAssertNil(error);

  simulator = [control createSessionForSimulatorConfiguration:simulatorConfiguration error:&error].simulator;
  XCTAssertNotNil(simulator);
  XCTAssertNil(error);
  XCTAssertEqualObjects(simulatorUUID, simulator.udid);
  [self assertTemporaryFileForSimulator:simulator exists:NO];

  XCTAssertTrue([control.simulatorPool freeSimulator:simulator error:nil]);
  XCTAssertNil(error);
}

- (void)testDoesNotReallocateDeletedDevice
{
  FBSimulator *simulator = [self createSession].simulator;
  NSString *simulatorUUID = simulator.udid;

  NSError *error = nil;
  XCTAssertTrue([simulator freeFromPoolWithError:&error]);
  XCTAssertNil(error);

  simulator = [self createSession].simulator;
  XCTAssertNotNil(simulator);
  XCTAssertNil(error);
  XCTAssertNotEqualObjects(simulatorUUID, simulator.udid);

  XCTAssertTrue([self.control.simulatorPool freeSimulator:simulator error:nil]);
  XCTAssertNil(error);
}

- (void)testRemovesDeletedDeviceFromSet
{
  FBSimulator *simulator = [self createSession].simulator;
  NSString *simulatorUUID = simulator.udid;

  NSError *error = nil;
  XCTAssertTrue([simulator freeFromPoolWithError:&error]);
  XCTAssertNil(error);

  NSOrderedSet *uuidSet = [self.control.simulatorPool.allSimulators valueForKey:@"udid"];
  XCTAssertFalse([uuidSet containsObject:simulatorUUID]);
}

- (void)testRemovesMultipleAllocatedDevicesFromSet
{
  NSMutableArray *simulators = [NSMutableArray array];
  NSMutableSet *simulatorUUIDs = [NSMutableSet set];

  for (NSInteger index = 0; index < 4; index++) {
    FBSimulator *simulator = [self createSession].simulator;
    [simulators addObject:simulator];
    [simulatorUUIDs addObject:simulator.udid];
  }

  NSError *error = nil;
  XCTAssertTrue([self.control.simulatorPool deleteAllWithError:&error]);
  XCTAssertNil(error);

  NSOrderedSet *uuidSet = [self.control.simulatorPool.allSimulators valueForKey:@"udid"];
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

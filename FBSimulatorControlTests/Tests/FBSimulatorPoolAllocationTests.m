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

- (NSString *)deviceSetPath
{
  return [NSTemporaryDirectory()
    stringByAppendingPathComponent:[NSString stringWithFormat:@"%@", NSStringFromClass(self.class)]];
}

- (void)assertFreesSimulator:(FBSimulator *)simulator
{
  NSError *error = nil;
  BOOL success = [self.control.simulatorPool freeSimulator:simulator error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

- (void)testReallocatesAndErasesFreedDevice
{
  FBSimulatorManagementOptions options = FBSimulatorManagementOptionsEraseOnFree | FBSimulatorManagementOptionsDeleteAllOnFirstStart;
  self.managementOptions = options;

  FBSimulator *simulator = [self createSession].simulator;
  NSString *simulatorUUID = simulator.udid;
  [self addTemporaryFileToSimulator:simulator];
  [self assertFreesSimulator:simulator];

  simulator = [self createSession].simulator;
  XCTAssertEqualObjects(simulatorUUID, simulator.udid);
  [self assertTemporaryFileForSimulator:simulator exists:NO];
  [self assertFreesSimulator:simulator];
}

- (void)testDoesNotReallocateDeletedDevice
{
  FBSimulator *simulator = [self createSession].simulator;
  NSString *simulatorUUID = simulator.udid;
  [self assertFreesSimulator:simulator];

  simulator = [self createSession].simulator;
  XCTAssertNotEqualObjects(simulatorUUID, simulator.udid);
  [self assertFreesSimulator:simulator];
}

- (void)testRemovesDeletedDeviceFromSet
{
  FBSimulator *simulator = [self createSession].simulator;
  NSString *simulatorUUID = simulator.udid;
  [self assertFreesSimulator:simulator];

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

  NSSet *uuidSet = [NSSet setWithArray:[self.control.simulatorPool.allSimulators valueForKey:@"udid"]];
  [simulatorUUIDs intersectSet:uuidSet];
  XCTAssertEqual(simulatorUUIDs.count, 0u);
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

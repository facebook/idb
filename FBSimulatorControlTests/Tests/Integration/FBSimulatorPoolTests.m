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
#import "FBSimulatorControlTestCase.h"
#import "FBSimulatorPoolTestCase.h"
#import "FBSimulatorControlAssertions.h"

@interface FBSimulatorPoolTests : FBSimulatorPoolTestCase

@end

@implementation FBSimulatorPoolTests

- (void)testDividesAllocatedAndUnAllocated
{
  NSArray *mockedSimulators = [self createPoolWithExistingSimDeviceSpecs:@[
    @{@"name" : @"iPhone 6S", @"state" : @(FBSimulatorStateShuttingDown)},
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateCreating)},
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateBooted)},
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateShutdown)},
    @{@"name" : @"iPad 2", @"state" : @(FBSimulatorStateBooted)},
    @{@"name" : @"iPad Air", @"state" : @(FBSimulatorStateBooted)},
    @{@"name" : @"iPad Air 2", @"state" : @(FBSimulatorStateCreating)},
    @{@"name" : @"iPhone 5", @"state" : @(FBSimulatorStateShutdown), @"os" : @"iOS 10.0"},
  ]];

  [self mockAllocationOfSimulatorsUDIDs:@[
    [mockedSimulators[0] udid],
    [mockedSimulators[3] udid]
  ]];

  NSArray *simulators = self.pool.allocatedSimulators;
  XCTAssertEqual(simulators.count, 2u);

  FBSimulator *simulator = simulators[0];
  XCTAssertEqualObjects(simulator.name, @"iPhone 6S");
  XCTAssertEqual(simulator.state, FBSimulatorStateShuttingDown);
  XCTAssertEqual(simulator.set, self.set);
  XCTAssertEqual(simulator.pool, self.pool);

  simulator = simulators[1];
  XCTAssertEqualObjects(simulator.name, @"iPhone 5");
  XCTAssertEqual(simulator.state, FBSimulatorStateBooted);
  XCTAssertEqual(simulator.set, self.set);
  XCTAssertEqual(simulator.pool, self.pool);

  simulators = self.pool.unallocatedSimulators;
  XCTAssertEqual(simulators.count, 6u);

  simulator = simulators[0];
  XCTAssertEqualObjects(simulator.name, @"iPhone 5");
  XCTAssertEqual(simulator.state, FBSimulatorStateCreating);
  XCTAssertEqual(simulator.set, self.set);
  XCTAssertNil(simulator.pool);

  simulator = simulators[1];
  XCTAssertEqualObjects(simulator.name, @"iPhone 5");
  XCTAssertEqual(simulator.state, FBSimulatorStateShutdown);
  XCTAssertEqual(simulator.set, self.set);
  XCTAssertNil(simulator.pool);

  simulator = simulators[2];
  XCTAssertEqualObjects(simulator.name, @"iPad 2");
  XCTAssertEqual(simulator.state, FBSimulatorStateBooted);
  XCTAssertEqual(simulator.set, self.set);
  XCTAssertNil(simulator.pool);

  simulator = simulators[3];
  XCTAssertEqualObjects(simulator.name, @"iPad Air");
  XCTAssertEqual(simulator.state, FBSimulatorStateBooted);
  XCTAssertEqual(simulator.set, self.set);
  XCTAssertNil(simulator.pool);

  simulator = simulators[4];
  XCTAssertEqualObjects(simulator.name, @"iPad Air 2");
  XCTAssertEqual(simulator.state, FBSimulatorStateCreating);
  XCTAssertEqual(simulator.set, self.set);
  XCTAssertNil(simulator.pool);

  simulator = simulators[5];
  XCTAssertEqualObjects(simulator.name, @"iPhone 5");
  XCTAssertEqual(simulator.state, FBSimulatorStateShutdown);
  XCTAssertEqual(simulator.set, self.set);
  XCTAssertNil(simulator.pool);
}

@end

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
  BOOL success = [self.control.pool freeSimulator:simulator error:&error];
  // Temporarily add some debug output to the error's userInfo.
  if (error) {
    NSError *firstUnderlyingError = (NSError *)error.userInfo[NSUnderlyingErrorKey];
    NSError *secondUnderlyingError = (NSError *)firstUnderlyingError.userInfo[NSUnderlyingErrorKey];
    NSString *path = secondUnderlyingError.userInfo[NSFilePathErrorKey];
    if (path) {
      FBTask *findTask = [[[[FBTaskBuilder
        withLaunchPath:@"/usr/bin/find" arguments:@[path]]
        withStdOutInMemory]
        withStdErrInMemory]
        build];
      [findTask startSynchronouslyWithTimeout:10.0f];
      FBTask *lsofTask = [[[[FBTaskBuilder
        withLaunchPath:@"/usr/sbin/lsof" arguments:@[@"+D", path]]
        withStdOutInMemory]
        withStdErrInMemory]
        build];
      [lsofTask startSynchronouslyWithTimeout:10.0f];
      NSMutableDictionary *userInfo = error.userInfo.mutableCopy;
      userInfo[@"debug.path"] = path ?: @"";
      userInfo[@"debug.lsofTask.stdout"] = lsofTask.stdOut ?: @"";
      userInfo[@"debug.lsofTask.stderr"] = lsofTask.stdErr ?: @"";
      userInfo[@"debug.findTask.stdout"] = findTask.stdOut ?: @"";
      userInfo[@"debug.findTask.stderr"] = findTask.stdErr ?: @"";
      error = [NSError errorWithDomain:error.domain code:error.code userInfo:userInfo];
    }
  }
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertNil(simulator.pool);
}

- (void)testReallocatesAndErasesFreedDevice
{
  FBSimulatorAllocationOptions options = self.allocationOptions;
  self.allocationOptions = options | FBSimulatorAllocationOptionsEraseOnFree;

  FBSimulator *simulator = [self assertObtainsSimulator];
  NSString *simulatorUUID = simulator.udid;
  [self addTemporaryFileToSimulator:simulator];
  [self assertFreesSimulator:simulator];

  simulator = [self assertObtainsSimulator];
  XCTAssertEqualObjects(simulatorUUID, simulator.udid);
  [self assertTemporaryFileForSimulator:simulator exists:NO];
  [self assertFreesSimulator:simulator];
}

- (void)testDoesNotReallocateDeletedDevice
{
  FBSimulatorAllocationOptions options = self.allocationOptions;
  self.allocationOptions = options | FBSimulatorAllocationOptionsDeleteOnFree;

  FBSimulator *simulator = [self assertObtainsSimulator];
  NSString *simulatorUUID = simulator.udid;
  [self assertFreesSimulator:simulator];

  simulator = [self assertObtainsSimulator];
  XCTAssertNotEqualObjects(simulatorUUID, simulator.udid);
  [self assertFreesSimulator:simulator];
}

- (void)testRemovesDeletedDeviceFromSet
{
  FBSimulatorAllocationOptions options = self.allocationOptions;
  self.allocationOptions = options | FBSimulatorAllocationOptionsDeleteOnFree;

  FBSimulator *simulator = [self assertObtainsSimulator];
  NSString *simulatorUUID = simulator.udid;
  [self assertFreesSimulator:simulator];

  NSOrderedSet *uuidSet = [self.control.pool.set.allSimulators valueForKey:@"udid"];
  XCTAssertFalse([uuidSet containsObject:simulatorUUID]);
}

- (void)testRemovesMultipleAllocatedDevicesFromSet
{
  NSMutableArray *simulators = [NSMutableArray array];
  NSMutableSet *simulatorUUIDs = [NSMutableSet set];

  for (NSInteger index = 0; index < 4; index++) {
    FBSimulator *simulator = [self assertObtainsSimulator];
    [simulators addObject:simulator];
    [simulatorUUIDs addObject:simulator.udid];
  }

  NSError *error = nil;
  XCTAssertTrue([self.control.pool.set deleteAllWithError:&error]);
  XCTAssertNil(error);

  NSSet *uuidSet = [NSSet setWithArray:[self.control.pool.set.allSimulators valueForKey:@"udid"]];
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

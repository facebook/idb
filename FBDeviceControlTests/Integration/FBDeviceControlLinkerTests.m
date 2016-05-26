/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import <FBDeviceControl/FBDeviceControl.h>

@interface FBDeviceControlLinkerTests : XCTestCase

@end

@implementation FBDeviceControlLinkerTests

+ (void)initialize
{
  if (!NSProcessInfo.processInfo.environment[FBControlCoreStderrLogging]) {
    setenv(FBControlCoreStderrLogging.UTF8String, "YES", 1);
  }
  if (!NSProcessInfo.processInfo.environment[FBControlCoreDebugLogging]) {
    setenv(FBControlCoreDebugLogging.UTF8String, "NO", 1);
  }
}

- (void)testLinksPrivateFrameworks
{
  [FBDeviceControlFrameworkLoader initializeEssentialFrameworks];
  [FBDeviceControlFrameworkLoader initializeXCodeFrameworks];
}

- (void)testConstructsDeviceSet
{
  NSError *error = nil;
  FBDeviceSet *deviceSet = [FBDeviceSet defaultSetWithLogger:FBControlCoreGlobalConfiguration.defaultLogger error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(deviceSet);
  XCTAssertNotNil(deviceSet.allDevices);
}

- (void)testLazilyFetchesDVTClasses
{
  NSError *error = nil;
  FBDeviceSet *deviceSet = [FBDeviceSet defaultSetWithLogger:FBControlCoreGlobalConfiguration.defaultLogger error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil([deviceSet.allDevices valueForKey:@"description"]);
  XCTAssertEqual(deviceSet.allDevices.count, [[[deviceSet.allDevices valueForKey:@"deviceOperator"] filteredArrayUsingPredicate:NSPredicate.notNullPredicate] count]);
}

- (void)testReadsFromMobileDevice
{
  NSArray<FBAMDevice *> *devices = [FBAMDevice allDevices];
  XCTAssertNotNil(devices);
}

@end

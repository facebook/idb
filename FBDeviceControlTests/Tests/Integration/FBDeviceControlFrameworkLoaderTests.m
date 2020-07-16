/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import <FBDeviceControl/FBDeviceControl.h>

@interface FBDeviceControlFrameworkLoaderTests : XCTestCase

@end

@implementation FBDeviceControlFrameworkLoaderTests

+ (void)initialize
{
  if (!NSProcessInfo.processInfo.environment[FBControlCoreStderrLogging]) {
    setenv(FBControlCoreStderrLogging.UTF8String, "YES", 1);
  }
  if (!NSProcessInfo.processInfo.environment[FBControlCoreDebugLogging]) {
    setenv(FBControlCoreDebugLogging.UTF8String, "NO", 1);
  }
}

- (void)testConstructsDeviceSet
{
  NSError *error = nil;
  FBDeviceSet *deviceSet = [FBDeviceSet setWithLogger:FBControlCoreGlobalConfiguration.defaultLogger delegate:nil ecidFilter:nil error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(deviceSet);
  XCTAssertNotNil(deviceSet.allDevices);
}

@end

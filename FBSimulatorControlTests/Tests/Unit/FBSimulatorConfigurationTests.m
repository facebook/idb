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

@interface FBSimulatorConfigurationTests : XCTestCase

@end

@implementation FBSimulatorConfigurationTests

- (void)testAllConfigurationsArePresent
{
  NSMutableArray<NSString *> *absentOSVersions = [NSMutableArray array];
  NSMutableArray<NSString *> *absentDeviceTypes = [NSMutableArray array];
  [FBSimulatorConfiguration allAvailableDefaultConfigurationsWithAbsentOSVersionsOut:&absentOSVersions absentDeviceTypesOut:&absentDeviceTypes];
  XCTAssertEqualObjects(absentOSVersions, @[]);
  XCTAssertEqualObjects(absentDeviceTypes, @[]);
}

@end

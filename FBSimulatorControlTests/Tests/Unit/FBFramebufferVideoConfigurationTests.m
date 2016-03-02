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

@interface FBFramebufferVideoConfigurationTests : XCTestCase

@end

@implementation FBFramebufferVideoConfigurationTests

- (void)testEqualityOfCopy
{
  FBFramebufferVideoConfiguration *config = [[[FBFramebufferVideoConfiguration withAutorecord:YES] withRoundingMethod:kCMTimeRoundingMethod_RoundTowardZero] withFileType:@"foo"];
  FBFramebufferVideoConfiguration *configCopy = [config copy];

  XCTAssertEqualObjects(config, configCopy);
}

- (void)testUnarchiving
{
  FBFramebufferVideoConfiguration *config = [[[FBFramebufferVideoConfiguration withAutorecord:NO] withRoundingMethod:kCMTimeRoundingMethod_RoundTowardNegativeInfinity] withFileType:@"bar"];
  NSData *configData = [NSKeyedArchiver archivedDataWithRootObject:config];
  FBFramebufferVideoConfiguration *configUnarchived = [NSKeyedUnarchiver unarchiveObjectWithData:configData];

  XCTAssertEqualObjects(config, configUnarchived);
}

@end

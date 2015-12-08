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

- (FBSimulatorConfiguration *)configuration
{
  return FBSimulatorConfiguration.defaultConfiguration;
}

- (void)testEqualityOfCopy
{
  FBSimulatorConfiguration *config = self.configuration;
  FBSimulatorConfiguration *configCopy = [config copy];

  XCTAssertEqualObjects(config.deviceName, configCopy.deviceName);
  XCTAssertEqualObjects(config.osVersionString, configCopy.osVersionString);
  XCTAssertEqualObjects(config, configCopy);
}

- (void)testUnarchiving
{
  FBSimulatorConfiguration *config = self.configuration;
  NSData *configData = [NSKeyedArchiver archivedDataWithRootObject:config];
  FBSimulatorConfiguration *configUnarchived = [NSKeyedUnarchiver unarchiveObjectWithData:configData];

  XCTAssertEqualObjects(config.deviceName, configUnarchived.deviceName);
  XCTAssertEqualObjects(config.osVersionString, configUnarchived.osVersionString);
  XCTAssertEqualObjects(config, configUnarchived);
}

@end

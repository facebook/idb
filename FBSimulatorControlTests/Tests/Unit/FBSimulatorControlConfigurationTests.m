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

@interface FBSimulatorControlConfigurationTests : XCTestCase

@end

@implementation FBSimulatorControlConfigurationTests

- (FBSimulatorControlConfiguration *)configuration
{
  return [FBSimulatorControlConfiguration
    configurationWithDeviceSetPath:nil
    options:FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart];
}

- (void)testEqualityOfCopy
{
  FBSimulatorControlConfiguration *config = self.configuration;
  FBSimulatorControlConfiguration *configCopy = [config copy];

  XCTAssertEqual(config.options, configCopy.options);
  XCTAssertEqualObjects(config, configCopy);
}

- (void)testUnarchiving
{
  FBSimulatorControlConfiguration *config = self.configuration;
  NSData *configData = [NSKeyedArchiver archivedDataWithRootObject:config];
  FBSimulatorControlConfiguration *configUnarchived = [NSKeyedUnarchiver unarchiveObjectWithData:configData];

  XCTAssertEqual(config.options, configUnarchived.options);
  XCTAssertEqualObjects(config, configUnarchived);
}

@end

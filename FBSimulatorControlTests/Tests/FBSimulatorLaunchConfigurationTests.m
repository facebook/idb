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

@interface FBSimulatorLaunchConfigurationTests : XCTestCase

@end

@implementation FBSimulatorLaunchConfigurationTests

- (FBSimulatorLaunchConfiguration *)configuration
{
  return [[[FBSimulatorLaunchConfiguration
    withLocaleNamed:@"en_US"]
    withOptions:FBSimulatorLaunchOptionsShowDebugWindow]
    scale75Percent];
}

- (void)testEqualityOfCopy
{
  FBSimulatorLaunchConfiguration *config = self.configuration;
  FBSimulatorLaunchConfiguration *configCopy = [config copy];

  XCTAssertEqual(config.options, configCopy.options);
  XCTAssertEqualObjects(config, configCopy);
}

- (void)testUnarchiving
{
  FBSimulatorLaunchConfiguration *config = self.configuration;
  NSData *configData = [NSKeyedArchiver archivedDataWithRootObject:config];
  FBSimulatorLaunchConfiguration *configUnarchived = [NSKeyedUnarchiver unarchiveObjectWithData:configData];

  XCTAssertEqual(config.options, configUnarchived.options);
  XCTAssertEqualObjects(config, configUnarchived);
}

@end

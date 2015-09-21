/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBProcessLaunchConfiguration.h>
#import <FBSimulatorControl/FBSimulatorApplication.h>

@interface FBProcessLaunchConfigurationTests : XCTestCase

@end

@implementation FBProcessLaunchConfigurationTests

- (void)testEqualityOfCopy
{
  FBSimulatorApplication *application = [[FBSimulatorApplication simulatorSystemApplications] firstObject];

  FBApplicationLaunchConfiguration *appLaunchConfig = [FBApplicationLaunchConfiguration
    configurationWithApplication:application
    arguments:@[@"FOOBAR"]
    environment:@{@"BING" : @"BAZ"}];
  FBApplicationLaunchConfiguration *appLaunchConfigCopy = [appLaunchConfig copy];

  XCTAssertEqualObjects(appLaunchConfig.application, appLaunchConfigCopy.application);
  XCTAssertEqualObjects(appLaunchConfig.arguments, appLaunchConfigCopy.arguments);
  XCTAssertEqualObjects(appLaunchConfig.environment, appLaunchConfigCopy.environment);
  XCTAssertEqualObjects(appLaunchConfig, appLaunchConfigCopy);

  FBAgentLaunchConfiguration *agentLaunchConfig = [FBAgentLaunchConfiguration
    configurationWithBinary:application.binary
    arguments:@[@"BINGBONG"]
    environment:@{@"FIB" : @"BLE"}];
  FBAgentLaunchConfiguration *agentLaunchConfigCopy = [agentLaunchConfig copy];

  XCTAssertEqualObjects(agentLaunchConfig.agentBinary, agentLaunchConfigCopy.agentBinary);
  XCTAssertEqualObjects(agentLaunchConfig.arguments, agentLaunchConfigCopy.arguments);
  XCTAssertEqualObjects(agentLaunchConfig.environment, agentLaunchConfigCopy.environment);
  XCTAssertEqualObjects(agentLaunchConfig, agentLaunchConfigCopy);
}

@end

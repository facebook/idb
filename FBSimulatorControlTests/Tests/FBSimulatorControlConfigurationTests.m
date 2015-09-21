/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <OCMock/OCMock.h>

#import <FBSimulatorControl/FBProcessLaunchConfiguration.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorApplication.h>
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorPool.h>
#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

@interface FBSimulatorControlConfigurationTests : XCTestCase

@end

@implementation FBSimulatorControlConfigurationTests

- (void)testEquality
{
  FBSimulatorApplication *application = [FBSimulatorApplication simulatorApplicationWithError:nil];

  FBSimulatorControlConfiguration *config = [FBSimulatorControlConfiguration
    configurationWithSimulatorApplication:application bucket:1 options:FBSimulatorManagementOptionsDeleteManagedSimulatorsOnFirstStart];
  FBSimulatorControlConfiguration *configCopy = [config copy];

  XCTAssertEqualObjects(config.simulatorApplication, configCopy.simulatorApplication);
  XCTAssertEqual(config.bucketID, configCopy.bucketID);
  XCTAssertEqual(config.options, configCopy.options);
  XCTAssertEqualObjects(config, configCopy);

  FBApplicationLaunchConfiguration *appLaunchConfig = [FBApplicationLaunchConfiguration
    configurationWithApplication:application arguments:@[@"FOOBAR"] environment:@{@"BING" : @"BAZ"}];
  FBApplicationLaunchConfiguration *appLaunchConfigCopy = [appLaunchConfig copy];

  XCTAssertEqualObjects(appLaunchConfig.application, appLaunchConfigCopy.application);
  XCTAssertEqualObjects(appLaunchConfig.arguments, appLaunchConfigCopy.arguments);
  XCTAssertEqualObjects(appLaunchConfig.environment, appLaunchConfigCopy.environment);
  XCTAssertEqualObjects(appLaunchConfig, appLaunchConfigCopy);

  FBAgentLaunchConfiguration *agentLaunchConfig = [FBAgentLaunchConfiguration
    configurationWithBinary:application.binary arguments:@[@"BINGBONG"] environment:@{@"FIB" : @"BLE"}];
  FBAgentLaunchConfiguration *agentLaunchConfigCopy = [agentLaunchConfig copy];

  XCTAssertEqualObjects(agentLaunchConfig.agentBinary, agentLaunchConfigCopy.agentBinary);
  XCTAssertEqualObjects(agentLaunchConfig.arguments, agentLaunchConfigCopy.arguments);
  XCTAssertEqualObjects(agentLaunchConfig.environment, agentLaunchConfigCopy.environment);
  XCTAssertEqualObjects(agentLaunchConfig, agentLaunchConfigCopy);
}

@end

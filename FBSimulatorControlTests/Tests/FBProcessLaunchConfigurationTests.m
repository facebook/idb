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

@interface FBProcessLaunchConfigurationTests : XCTestCase

@end

@implementation FBProcessLaunchConfigurationTests

- (FBSimulatorApplication *)application
{
  return [[FBSimulatorApplication simulatorSystemApplications] firstObject];
}

- (FBApplicationLaunchConfiguration *)applicationLaunchConfiguration1
{
  return [FBApplicationLaunchConfiguration
    configurationWithApplication:self.application
    arguments:@[@"FOOBAR"]
    environment:@{@"BING" : @"BAZ"}];
}

- (FBAgentLaunchConfiguration *)agentLaunchConfiguration1
{
  return [FBAgentLaunchConfiguration
   configurationWithBinary:self.application.binary
   arguments:@[@"BINGBONG"]
   environment:@{@"FIB" : @"BLE"}];
}

- (void)testEqualityOfCopy
{
  FBApplicationLaunchConfiguration *appLaunch = [self.applicationLaunchConfiguration1 copy];
  FBApplicationLaunchConfiguration *appLaunchCopy = [appLaunch copy];

  XCTAssertEqualObjects(appLaunch.application, appLaunchCopy.application);
  XCTAssertEqualObjects(appLaunch.arguments, appLaunchCopy.arguments);
  XCTAssertEqualObjects(appLaunch.environment, appLaunchCopy.environment);
  XCTAssertEqualObjects(appLaunch, appLaunchCopy);

  FBAgentLaunchConfiguration *agentLaunch = self.agentLaunchConfiguration1;
  FBAgentLaunchConfiguration *agentLaunchCopy = [agentLaunch copy];

  XCTAssertEqualObjects(agentLaunch.agentBinary, agentLaunchCopy.agentBinary);
  XCTAssertEqualObjects(agentLaunch.arguments, agentLaunchCopy.arguments);
  XCTAssertEqualObjects(agentLaunch.environment, agentLaunchCopy.environment);
  XCTAssertEqualObjects(agentLaunch, agentLaunchCopy);
}

- (void)testArchiving
{
  FBApplicationLaunchConfiguration *appLaunch = [self.applicationLaunchConfiguration1 copy];
  NSData *appLaunchData = [NSKeyedArchiver archivedDataWithRootObject:appLaunch];
  FBApplicationLaunchConfiguration *appLaunchUnarchived = [NSKeyedUnarchiver unarchiveObjectWithData:appLaunchData];

  XCTAssertEqualObjects(appLaunch.application, appLaunchUnarchived.application);
  XCTAssertEqualObjects(appLaunch.arguments, appLaunchUnarchived.arguments);
  XCTAssertEqualObjects(appLaunch.environment, appLaunchUnarchived.environment);
  XCTAssertEqualObjects(appLaunch, appLaunchUnarchived);

  FBAgentLaunchConfiguration *agentLaunch = [self.agentLaunchConfiguration1 copy];
  NSData *agentLaunchData = [NSKeyedArchiver archivedDataWithRootObject:agentLaunch];
  FBAgentLaunchConfiguration *agentLaunchUnarchived = [NSKeyedUnarchiver unarchiveObjectWithData:agentLaunchData];

  XCTAssertEqualObjects(agentLaunch.agentBinary, agentLaunchUnarchived.agentBinary);
  XCTAssertEqualObjects(agentLaunch.arguments, agentLaunchUnarchived.arguments);
  XCTAssertEqualObjects(agentLaunch.environment, agentLaunchUnarchived.environment);
  XCTAssertEqualObjects(agentLaunch, agentLaunchUnarchived);
}

@end

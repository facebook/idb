/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBSimulatorControlAssertions.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorLaunchTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorLaunchTests

- (FBSimulator *)doTestApplicationLaunches:(FBApplicationLaunchConfiguration *)appLaunch
{
  return [self
    assertSimulatorWithConfiguration:self.simulatorConfiguration
    boots:self.bootConfiguration
    thenLaunchesApplication:appLaunch];
}

- (void)testLaunchesSingleSimulator:(FBSimulatorConfiguration *)configuration
{
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithConfiguration:configuration bootConfiguration:self.bootConfiguration];
  if (!simulator) {
    return;
  }

  [self assertSimulatorBooted:simulator];
  [self assertShutdownSimulatorAndTerminateSession:simulator];
}

- (void)testLaunchesiPhone
{
  [self testLaunchesSingleSimulator:[FBSimulatorConfiguration.defaultConfiguration withDeviceModel:SimulatorControlTestsDefaultiPhoneModel]];
}

- (void)testLaunchesiPad
{
  [self testLaunchesSingleSimulator:[FBSimulatorConfiguration.defaultConfiguration withDeviceModel:SimulatorControlTestsDefaultiPadModel]];
}

- (void)testLaunchesWatch
{
  [self testLaunchesSingleSimulator:[FBSimulatorConfiguration.defaultConfiguration withDeviceModel:FBDeviceModelAppleWatch42mm]];
}

- (void)testLaunchesTV
{
  [self testLaunchesSingleSimulator:[FBSimulatorConfiguration.defaultConfiguration withDeviceModel:FBDeviceModelAppleTV]];
}

- (void)testLaunchesSafariApplication
{
  [self doTestApplicationLaunches:self.safariAppLaunch];
}

- (void)testCanUninstallApplication
{
  FBBundleDescriptor *application = self.tableSearchApplication;
  FBApplicationLaunchConfiguration *launch = self.tableSearchAppLaunch;
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithInstalledApplication:application];

  NSError *error = nil;
  BOOL success = [[simulator launchApplication:launch] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self assertSimulator:simulator isRunningApplicationFromConfiguration:launch];

  success = [[simulator uninstallApplicationWithBundleID:application.identifier] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

@end

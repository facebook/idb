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

- (FBSimulator *)doTestApplicationRelaunches:(FBApplicationLaunchConfiguration *)appLaunch
{
  return [self
    assertSimulatorWithConfiguration:self.simulatorConfiguration
    boots:self.bootConfiguration
    launchesThenRelaunchesApplication:appLaunch];
}

- (FBSimulator *)doTestApplication:(FBApplicationBundle *)application launches:(FBApplicationLaunchConfiguration *)appLaunch
{
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithConfiguration:self.simulatorConfiguration bootConfiguration:self.bootConfiguration];
  [self assertSimulator:simulator installs:application];
  return [self assertSimulator:simulator launches:appLaunch];
}

- (void)testLaunchesSingleSimulator:(FBSimulatorConfiguration *)configuration
{
  FBSimulatorBootConfiguration *bootConfiguration = self.bootConfiguration;
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithConfiguration:configuration bootConfiguration:self.bootConfiguration];
  if (!simulator) {
    return;
  }

  [self assertSimulatorBooted:simulator];
  [self assertShutdownSimulatorAndTerminateSession:simulator];
  [self.assert shutdownNotificationsFired:bootConfiguration];
}

- (void)testLaunchesiPhone
{
  [self testLaunchesSingleSimulator:[FBSimulatorConfiguration withDeviceModel:FBDeviceModeliPhone5]];
}

- (void)testLaunchesiPad
{
  [self testLaunchesSingleSimulator:[FBSimulatorConfiguration withDeviceModel:FBDeviceModeliPadAir]];
}

- (void)testLaunchesWatch
{
  [self testLaunchesSingleSimulator:[FBSimulatorConfiguration withDeviceModel:FBDeviceModelAppleWatch42mm]];
}

- (void)testLaunchesTV
{
  [self testLaunchesSingleSimulator:[FBSimulatorConfiguration withDeviceModel:FBDeviceModelAppleTV]];
}

- (void)testLaunchesPreviousiOSVersionAndAwaitsServices
{
  FBSimulatorBootOptions options = self.bootConfiguration.options | FBSimulatorBootOptionsAwaitServices;
  self.bootConfiguration = [self.bootConfiguration withOptions:options];
  [self testLaunchesSingleSimulator:[[FBSimulatorConfiguration withDeviceModel:FBDeviceModeliPhone5] withOSNamed:FBOSVersionNameiOS_9_3]];
}

- (void)testLaunchesiOSVersion8AndAwaitsServices
{
  FBSimulatorBootOptions options = self.bootConfiguration.options | FBSimulatorBootOptionsAwaitServices;
  self.bootConfiguration = [self.bootConfiguration withOptions:options];
  [self testLaunchesSingleSimulator:[[FBSimulatorConfiguration withDeviceModel:FBDeviceModeliPhone5] withOSNamed:FBOSVersionNameiOS_8_3]];
}

- (void)testLaunchesMultipleSimulators
{
  // Simulator Pool management is single threaded since it relies on unsynchronised mutable state
  // Create the sessions in sequence, then boot them in paralell.
  FBSimulator *simulator1 = [self assertObtainsSimulatorWithConfiguration:[FBSimulatorConfiguration withDeviceModel:FBDeviceModeliPhone5]];
  if (!simulator1) {
    return;
  }
  FBSimulator *simulator2 = [self assertObtainsSimulatorWithConfiguration:[FBSimulatorConfiguration withDeviceModel:FBDeviceModeliPhone5]];
  if (!simulator2) {
    return;
  }
  FBSimulator *simulator3 = [self assertObtainsSimulatorWithConfiguration:[FBSimulatorConfiguration withDeviceModel:FBDeviceModeliPadAir]];
  if (!simulator3) {
    return;
  }

  XCTAssertEqual(self.control.pool.allocatedSimulators.count, 3u);
  XCTAssertEqual(([[NSSet setWithArray:@[simulator1.udid, simulator2.udid, simulator3.udid]] count]), 3u);

  NSError *error = nil;
  BOOL success = [[simulator1 bootWithConfiguration:self.bootConfiguration] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  success = [[simulator2 bootWithConfiguration:self.bootConfiguration] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  success = [[simulator3 bootWithConfiguration:self.bootConfiguration] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  NSArray *simulators = @[simulator1, simulator2, simulator3];
  for (FBSimulator *simulator in simulators) {
    [self assertSimulatorBooted:simulator];
  }

  XCTAssertEqual([NSSet setWithArray:[simulators valueForKeyPath:@"launchdProcess.processIdentifier"]].count, 3u);

  for (FBSimulator *simulator in simulators) {
    [self assertShutdownSimulatorAndTerminateSession:simulator];
  }

  XCTAssertEqual(self.control.pool.allocatedSimulators.count, 0u);
}

- (void)testLaunchesSafariApplication
{
  [self doTestApplicationLaunches:self.safariAppLaunch];
}

- (void)testRelaunchesSafariApplication
{
  [self doTestApplicationRelaunches:self.safariAppLaunch];
}

- (void)testLaunchesSampleApplication
{
  [self doTestApplication:self.tableSearchApplication launches:self.tableSearchAppLaunch];
}

- (void)testCanUninstallApplication
{
  FBApplicationBundle *application = self.tableSearchApplication;
  FBApplicationLaunchConfiguration *launch = self.tableSearchAppLaunch;
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithInstalledApplication:application];

  NSError *error = nil;
  BOOL success = [[simulator launchApplication:launch] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self assertSimulator:simulator isRunningApplicationFromConfiguration:launch];

  success = [[simulator uninstallApplicationWithBundleID:application.bundleID] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

@end

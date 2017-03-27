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

- (FBSimulator *)testApplication:(FBApplicationDescriptor *)application launches:(FBApplicationLaunchConfiguration *)appLaunch
{
  return [self
    assertSimulatorWithConfiguration:self.simulatorConfiguration
    launches:self.simulatorLaunchConfiguration
    thenLaunchesApplication:application
    withApplicationLaunchConfiguration:appLaunch];
}

- (FBSimulator *)testApplication:(FBApplicationDescriptor *)application relaunches:(FBApplicationLaunchConfiguration *)appLaunch
{
  return [self
    assertSimulatorWithConfiguration:self.simulatorConfiguration
    relaunches:self.simulatorLaunchConfiguration
    thenLaunchesApplication:application
    withApplicationLaunchConfiguration:appLaunch];
}

- (void)testLaunchesSingleSimulator:(FBSimulatorConfiguration *)configuration
{
  FBSimulatorBootConfiguration *launchConfiguration = self.simulatorLaunchConfiguration;
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithConfiguration:configuration launchConfiguration:self.simulatorLaunchConfiguration];
  if (!simulator) {
    return;
  }

  [self assertSimulatorBooted:simulator];
  XCTAssertEqual(simulator.history.launchedAgentProcesses.count, 0u);
  XCTAssertEqual(simulator.history.launchedApplicationProcesses.count, 0u);

  [self assertShutdownSimulatorAndTerminateSession:simulator];
  [self.assert shutdownNotificationsFired:launchConfiguration];
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
  [self testLaunchesSingleSimulator:[FBSimulatorConfiguration withDeviceModel:FBDeviceModelAppleTV1080p]];
}

- (void)testLaunchesPreviousiOSVersionAndAwaitsServices
{
  FBSimulatorBootOptions options = self.simulatorLaunchConfiguration.options | FBSimulatorBootOptionsAwaitServices;
  self.simulatorLaunchConfiguration = [self.simulatorLaunchConfiguration withOptions:options];
  [self testLaunchesSingleSimulator:[[FBSimulatorConfiguration withDeviceModel:FBDeviceModeliPhone5] withOSNamed:FBOSVersionNameiOS_9_3]];
}

- (void)testLaunchesiOSVersion8AndAwaitsServices
{
  FBSimulatorBootOptions options = self.simulatorLaunchConfiguration.options | FBSimulatorBootOptionsAwaitServices;
  self.simulatorLaunchConfiguration = [self.simulatorLaunchConfiguration withOptions:options];
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
  BOOL success = [simulator1 bootSimulator:self.simulatorLaunchConfiguration error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
  success = [simulator2 bootSimulator:self.simulatorLaunchConfiguration error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
  success = [simulator3 bootSimulator:self.simulatorLaunchConfiguration error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  NSArray *simulators = @[simulator1, simulator2, simulator3];
  for (FBSimulator *simulator in simulators) {
    XCTAssertEqual(simulator.history.launchedAgentProcesses.count, 0u);
    XCTAssertEqual(simulator.history.launchedApplicationProcesses.count, 0u);
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
  [self testApplication:self.safariApplication launches:self.safariAppLaunch];
}

- (void)testRelaunchesSafariApplication
{
  [self testApplication:self.safariApplication relaunches:self.safariAppLaunch];
}

- (void)testLaunchesSampleApplication
{
  [self testApplication:self.tableSearchApplication launches:self.tableSearchAppLaunch];
}

- (void)testRelaunchesSampleApplication
{
  [self testApplication:self.tableSearchApplication relaunches:self.tableSearchAppLaunch];
}

- (void)testCanUninstallApplication
{
  FBApplicationDescriptor *application = self.tableSearchApplication;
  FBApplicationLaunchConfiguration *launch = self.tableSearchAppLaunch;
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithInstalledApplication:application];

  NSError *error = nil;
  BOOL success = [simulator launchApplication:launch error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self assertLastLaunchedApplicationIsRunning:simulator];

  success = [simulator uninstallApplicationWithBundleID:application.bundleID error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

@end

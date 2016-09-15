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
  FBSimulatorLaunchConfiguration *launchConfiguration = self.simulatorLaunchConfiguration;
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithConfiguration:configuration launchConfiguration:self.simulatorLaunchConfiguration];

  [self assertSimulatorBooted:simulator];
  XCTAssertEqual(simulator.history.launchedAgentProcesses.count, 0u);
  XCTAssertEqual(simulator.history.launchedApplicationProcesses.count, 0u);

  [self assertShutdownSimulatorAndTerminateSession:simulator];
  [self.assert shutdownNotificationsFired:launchConfiguration];
}

- (void)testLaunchesiPhone
{
  [self testLaunchesSingleSimulator:FBSimulatorConfiguration.iPhone5];
}

- (void)testLaunchesiPad
{
  [self testLaunchesSingleSimulator:FBSimulatorConfiguration.iPad2];
}

- (void)testLaunchesWatch
{
  [self testLaunchesSingleSimulator:FBSimulatorConfiguration.watch42mm];
}

- (void)testLaunchesTV
{
  [self testLaunchesSingleSimulator:FBSimulatorConfiguration.appleTV1080p];
}

- (void)testLaunchesMultipleSimulators
{
  // Simulator Pool management is single threaded since it relies on unsynchronised mutable state
  // Create the sessions in sequence, then boot them in paralell.
  FBSimulator *simulator1 = [self assertObtainsSimulatorWithConfiguration:FBSimulatorConfiguration.iPhone5];
  FBSimulator *simulator2 = [self assertObtainsSimulatorWithConfiguration:FBSimulatorConfiguration.iPhone5];
  FBSimulator *simulator3 = [self assertObtainsSimulatorWithConfiguration:FBSimulatorConfiguration.iPad2];

  XCTAssertEqual(self.control.pool.allocatedSimulators.count, 3u);
  XCTAssertEqual(([[NSSet setWithArray:@[simulator1.udid, simulator2.udid, simulator3.udid]] count]), 3u);

  [self assertInteractionSuccessful:[simulator1.interact bootSimulator:self.simulatorLaunchConfiguration]];
  [self assertInteractionSuccessful:[simulator2.interact bootSimulator:self.simulatorLaunchConfiguration]];
  [self assertInteractionSuccessful:[simulator3.interact bootSimulator:self.simulatorLaunchConfiguration]];

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
  FBSimulator *simulator = [self assertObtainsSimulator];
  FBApplicationDescriptor *application = self.tableSearchApplication;
  FBApplicationLaunchConfiguration *launch = self.tableSearchAppLaunch;

  [self.assert consumeAllNotifications];
  [self assertInteractionSuccessful:[[[simulator.interact bootSimulator:self.simulatorLaunchConfiguration] installApplication:application] launchApplication:launch]];
  [self assertLastLaunchedApplicationIsRunning:simulator];
  [self assertInteractionSuccessful:[simulator.interact uninstallApplicationWithBundleID:application.bundleID]];
}

@end

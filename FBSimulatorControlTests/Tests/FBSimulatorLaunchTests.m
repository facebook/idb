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

- (void)testLaunchesSafariApplication
{
  FBSimulator *simulator = [self obtainSimulator];
  FBApplicationLaunchConfiguration *appLaunch = self.safariAppLaunch;

  [self.assert consumeAllNotifications];
  [self assertInteractionSuccessful:[[simulator.interact bootSimulator:self.simulatorLaunchConfiguration] launchApplication:appLaunch]];

  [self.assert bootingNotificationsFired];
  [self.assert consumeNotification:FBSimulatorApplicationProcessDidLaunchNotification];
  [self.assert noNotificationsToConsume];
  [self assertSimulatorBooted:simulator];
}

- (void)testRelaunchesSafariApplication
{
  FBSimulator *simulator = [self obtainSimulator];
  FBApplicationLaunchConfiguration *appLaunch = self.safariAppLaunch;

  [self.assert consumeAllNotifications];
  [self assertInteractionSuccessful:[[simulator.interact bootSimulator:self.simulatorLaunchConfiguration] launchApplication:appLaunch]];

  [self.assert bootingNotificationsFired];
  [self.assert consumeNotification:FBSimulatorApplicationProcessDidLaunchNotification];
  [self.assert noNotificationsToConsume];
  [self assertSimulatorBooted:simulator];

  [self assertInteractionSuccessful:simulator.interact.relaunchLastLaunchedApplication];
  [self.assert consumeNotification:FBSimulatorApplicationProcessDidTerminateNotification];
  [self.assert consumeNotification:FBSimulatorApplicationProcessDidLaunchNotification];

  [self.assert noNotificationsToConsume];
}

- (void)testLaunchesSampleApplication
{
  FBSimulator *simulator = [self obtainSimulator];
  FBSimulatorApplication *application = self.tableSearchApplication;
  FBApplicationLaunchConfiguration *appLaunch = self.tableSearchAppLaunch;

  [self.assert consumeAllNotifications];
  [self assertInteractionSuccessful:[[[simulator.interact bootSimulator:self.simulatorLaunchConfiguration] installApplication:application] launchApplication:appLaunch]];
  [self assertLastLaunchedApplicationIsRunning:simulator];

  [self.assert bootingNotificationsFired];
  [self.assert consumeNotification:FBSimulatorApplicationProcessDidLaunchNotification];
  [self.assert noNotificationsToConsume];
  [self assertSimulatorBooted:simulator];
}

- (void)testLaunchesSingleSimulator:(FBSimulatorConfiguration *)configuration
{
  NSError *error = nil;
  if (![configuration checkRuntimeRequirementsReturningError:&error]) {
    NSLog(@"Could not run test for configuration %@ since: %@", configuration, error);
    return;
  }

  FBSimulator *simulator = [self obtainSimulatorWithConfiguration:configuration];
  [self.assert noNotificationsToConsume];

  [self assertInteractionSuccessful:[simulator.interact bootSimulator:self.simulatorLaunchConfiguration]];
  [self.assert bootingNotificationsFired];
  [self.assert noNotificationsToConsume];

  XCTAssertEqual(simulator.state, FBSimulatorStateBooted);
  XCTAssertEqual(simulator.history.launchedAgentProcesses.count, 0u);
  XCTAssertEqual(simulator.history.launchedApplicationProcesses.count, 0u);
  [self assertSimulatorBooted:simulator];

  [self assertShutdownSimulatorAndTerminateSession:simulator];
  [self.assert shutdownNotificationsFired];
  [self.assert noNotificationsToConsume];
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
  FBSimulator *simulator1 = [self obtainSimulatorWithConfiguration:FBSimulatorConfiguration.iPhone5];
  FBSimulator *simulator2 = [self obtainSimulatorWithConfiguration:FBSimulatorConfiguration.iPhone5];
  FBSimulator *simulator3 = [self obtainSimulatorWithConfiguration:FBSimulatorConfiguration.iPad2];

  XCTAssertEqual(self.control.simulatorPool.allocatedSimulators.count, 3u);
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

  XCTAssertEqual([NSSet setWithArray:[simulators valueForKeyPath:@"launchdSimProcess.processIdentifier"]].count, 3u);

  for (FBSimulator *simulator in simulators) {
    [self assertShutdownSimulatorAndTerminateSession:simulator];
  }

  XCTAssertEqual(self.control.simulatorPool.allocatedSimulators.count, 0u);
}

@end

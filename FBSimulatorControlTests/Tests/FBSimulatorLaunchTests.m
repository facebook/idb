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

- (NSArray *)expectedBootNotificationNames
{
  return @[FBSimulatorDidLaunchNotification];
}

- (NSArray *)expectedShutdownNotificationNames
{
  return @[FBSimulatorDidTerminateNotification];
}

- (void)testLaunchesSafariApplication
{
  FBSimulatorSession *session = [self createSession];
  FBApplicationLaunchConfiguration *appLaunch = self.safariAppLaunch;

  [self.assert consumeAllNotifications];
  [self assertInteractionSuccessful:[[session.interact bootSimulator:self.simulatorLaunchConfiguration] launchApplication:appLaunch]];

  [self.assert consumeNotifications:self.expectedBootNotificationNames];
  [self.assert consumeNotification:FBSimulatorApplicationProcessDidLaunchNotification];
  [self.assert noNotificationsToConsume];

  XCTAssertNotNil(session.simulator.launchInfo);
}

- (void)testRelaunchesSafariApplication
{
  FBSimulatorSession *session = [self createSession];
  FBApplicationLaunchConfiguration *appLaunch = self.safariAppLaunch;

  [self.assert consumeAllNotifications];
  [self assertInteractionSuccessful:[[session.interact bootSimulator:self.simulatorLaunchConfiguration] launchApplication:appLaunch]];

  [self.assert consumeNotifications:self.expectedBootNotificationNames];
  [self.assert consumeNotification:FBSimulatorApplicationProcessDidLaunchNotification];
  [self.assert noNotificationsToConsume];

  XCTAssertNotNil(session.simulator.launchInfo);

  [self assertInteractionSuccessful:session.interact.terminateLastLaunchedApplication];
  [self.assert consumeNotification:FBSimulatorApplicationProcessDidTerminateNotification];

  [self assertInteractionSuccessful:session.interact.relaunchLastLaunchedApplication];
  [self.assert consumeNotification:FBSimulatorApplicationProcessDidLaunchNotification];

  [self.assert noNotificationsToConsume];
}

- (void)testLaunchesSampleApplication
{
  FBSimulatorSession *session = [self createSession];
  FBApplicationLaunchConfiguration *appLaunch = self.tableSearchAppLaunch;

  [self.assert consumeAllNotifications];
  [self assertInteractionSuccessful:[[[session.interact bootSimulator:self.simulatorLaunchConfiguration] installApplication:appLaunch.application] launchApplication:appLaunch]];

  [self.assert consumeNotifications:self.expectedBootNotificationNames];
  [self.assert consumeNotification:FBSimulatorApplicationProcessDidLaunchNotification];
  [self.assert noNotificationsToConsume];

  XCTAssertNotNil(session.simulator.launchInfo);
}

- (void)testLaunchesSingleSimulator:(FBSimulatorConfiguration *)configuration
{
  NSError *error = nil;
  if (![configuration checkRuntimeRequirementsReturningError:&error]) {
    NSLog(@"Could not run test for configuration %@ since: %@", configuration, error);
    return;
  }

  FBSimulatorSession *session = [self createSessionWithConfiguration:configuration];
  XCTAssertEqual(session.state, FBSimulatorSessionStateNotStarted);
  [self.assert noNotificationsToConsume];

  [self assertInteractionSuccessful:[session.interact bootSimulator:self.simulatorLaunchConfiguration]];
  XCTAssertEqual(session.state, FBSimulatorSessionStateStarted);
  [self.assert consumeNotifications:self.expectedBootNotificationNames];
  [self.assert noNotificationsToConsume];

  XCTAssertEqual(session.simulator.state, FBSimulatorStateBooted);
  XCTAssertEqual(session.history.launchedAgentProcesses.count, 0u);
  XCTAssertEqual(session.history.launchedApplicationProcesses.count, 0u);
  XCTAssertNotNil(session.simulator.launchInfo);

  [self assertShutdownSimulatorAndTerminateSession:session];
  XCTAssertEqual(session.state, FBSimulatorSessionStateEnded);
  [self.assert consumeNotifications:self.expectedShutdownNotificationNames];
  [self.assert noNotificationsToConsume];

  XCTAssertNil(session.simulator.launchInfo);
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
  FBSimulatorSession *session1 = [self createSessionWithConfiguration:FBSimulatorConfiguration.iPhone5];
  XCTAssertEqual(session1.state, FBSimulatorSessionStateNotStarted);

  FBSimulatorSession *session2 = [self createSessionWithConfiguration:FBSimulatorConfiguration.iPhone5];
  XCTAssertEqual(session2.state, FBSimulatorSessionStateNotStarted);

  FBSimulatorSession *session3 = [self createSessionWithConfiguration:FBSimulatorConfiguration.iPad2];
  XCTAssertEqual(session3.state, FBSimulatorSessionStateNotStarted);

  XCTAssertEqual(self.control.simulatorPool.allocatedSimulators.count, 3u);
  XCTAssertEqual(([[NSSet setWithArray:@[session1.simulator.udid, session2.simulator.udid, session3.simulator.udid]] count]), 3u);

  [self assertInteractionSuccessful:[session1.interact bootSimulator:self.simulatorLaunchConfiguration]];
  [self assertInteractionSuccessful:[session2.interact bootSimulator:self.simulatorLaunchConfiguration]];
  [self assertInteractionSuccessful:[session3.interact bootSimulator:self.simulatorLaunchConfiguration]];

  NSArray *sessions = @[session1, session2, session3];
  for (FBSimulatorSession *session in sessions) {
    XCTAssertEqual(session.simulator.state, FBSimulatorStateBooted);
    XCTAssertEqual(session.state, FBSimulatorSessionStateStarted);
    XCTAssertEqual(session.history.launchedAgentProcesses.count, 0u);
    XCTAssertEqual(session.history.launchedApplicationProcesses.count, 0u);
    XCTAssertNotNil(session.simulator.launchInfo);
  }

  XCTAssertEqual([NSSet setWithArray:[sessions valueForKeyPath:@"simulator.launchInfo.simulatorProcess.processIdentifier"]].count, 3u);
  XCTAssertEqual([NSSet setWithArray:[sessions valueForKeyPath:@"simulator.launchInfo.launchdProcess.processIdentifier"]].count, 3u);

  for (FBSimulatorSession *session in sessions) {
    [self assertShutdownSimulatorAndTerminateSession:session];
    XCTAssertNil(session.simulator.launchInfo);
    XCTAssertEqual(session.state, FBSimulatorSessionStateEnded);
  }

  XCTAssertEqual(self.control.simulatorPool.allocatedSimulators.count, 0u);
}

@end

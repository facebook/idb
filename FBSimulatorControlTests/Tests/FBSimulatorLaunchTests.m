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
#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorLaunchTests : FBSimulatorControlTestCase

@end

@interface FBSimulatorLaunchTests_DefaultSet : FBSimulatorLaunchTests

@end

@interface FBSimulatorLaunchTests_CustomSet : FBSimulatorLaunchTests

@end

@implementation FBSimulatorLaunchTests

- (void)doTestLaunchesSingleSimulator
{
  FBSimulatorSession *session = [self createSession];
  XCTAssertEqual(session.state, FBSimulatorSessionStateNotStarted);
  [self.assert noNotificationsToConsume];

  [self assertInteractionSuccessful:session.interact.bootSimulator];
  XCTAssertEqual(session.state, FBSimulatorSessionStateStarted);
  [self.assert consumeNotification:FBSimulatorSessionDidStartNotification];
  [self.assert consumeNotification:FBSimulatorDidLaunchNotification];
  [self.assert noNotificationsToConsume];

  XCTAssertEqual(session.simulator.state, FBSimulatorStateBooted);
  XCTAssertEqual(session.history.launchedAgents.count, 0u);
  XCTAssertEqual(session.history.launchedApplications.count, 0u);
  XCTAssertNotNil(session.simulator.launchInfo);

  [self assertShutdownSimulatorAndTerminateSession:session];
  XCTAssertEqual(session.state, FBSimulatorSessionStateEnded);
  XCTAssertNil(session.simulator.launchInfo);
  [self.assert consumeNotification:FBSimulatorDidTerminateNotification];
  [self.assert consumeNotification:FBSimulatorSessionDidEndNotification];
  [self.assert noNotificationsToConsume];
}

- (void)doTestLaunchesMultipleSimulatorsConcurrently
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

  [self assertInteractionSuccessful:session1.interact.bootSimulator];
  [self assertInteractionSuccessful:session2.interact.bootSimulator];
  [self assertInteractionSuccessful:session3.interact.bootSimulator];

  NSArray *sessions = @[session1, session2, session3];
  for (FBSimulatorSession *session in sessions) {
    XCTAssertEqual(session.simulator.state, FBSimulatorStateBooted);
    XCTAssertEqual(session.state, FBSimulatorSessionStateStarted);
    XCTAssertEqual(session.history.launchedAgents.count, 0u);
    XCTAssertEqual(session.history.launchedApplications.count, 0u);
    XCTAssertNotNil(session.simulator.launchInfo);
  }

  XCTAssertEqual([NSSet setWithArray:[sessions valueForKeyPath:@"simulator.launchInfo.simulatorProcess.processIdentifier"]].count, 3u);
  XCTAssertEqual([NSSet setWithArray:[sessions valueForKeyPath:@"simulator.launchInfo.launchdProcess.processIdentifier"]].count, 3u);
  XCTAssertEqual([NSSet setWithArray:[sessions valueForKeyPath:@"simulator.launchInfo.simulatorApplication"]].count, 3u);

  for (FBSimulatorSession *session in sessions) {
    [self assertShutdownSimulatorAndTerminateSession:session];
    XCTAssertNil(session.simulator.launchInfo);
    XCTAssertEqual(session.state, FBSimulatorSessionStateEnded);
  }

  XCTAssertEqual(self.control.simulatorPool.allocatedSimulators.count, 0u);
}

@end

@implementation FBSimulatorLaunchTests_DefaultSet

- (NSString *)deviceSetPath
{
  return nil;
}

- (void)testLaunchesSingleSimulator
{
  [self doTestLaunchesSingleSimulator];
}

- (void)testLaunchesMultipleSimulatorsConcurrently
{
  [self doTestLaunchesMultipleSimulatorsConcurrently];
}

@end

@implementation FBSimulatorLaunchTests_CustomSet

- (NSString *)deviceSetPath
{
  return [NSTemporaryDirectory() stringByAppendingPathComponent:@"FBSimulatorControlSimulatorLaunchTests_CustomSet"];
}

- (void)testLaunchesSingleSimulator
{
  if (!FBSimulatorControlStaticConfiguration.supportsCustomDeviceSets) {
    NSLog(@"-[%@ %@] can't run as Custom Device Sets are not supported for this version of Xcode", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    return;
  }
  [self doTestLaunchesSingleSimulator];
}

- (void)testLaunchesMultipleSimulatorsConcurrently
{
  if (!FBSimulatorControlStaticConfiguration.supportsCustomDeviceSets) {
    NSLog(@"-[%@ %@] can't run as Custom Device Sets are not supported for this version of Xcode", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    return;
  }
  [self doTestLaunchesMultipleSimulatorsConcurrently];
}

@end

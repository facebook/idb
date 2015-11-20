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

@interface FBSimulatorControlSimulatorLaunchTests : FBSimulatorControlTestCase

@end

@interface FBSimulatorControlSimulatorLaunchTests_DefaultSet : FBSimulatorControlSimulatorLaunchTests

@end

@interface FBSimulatorControlSimulatorLaunchTests_CustomSet : FBSimulatorControlSimulatorLaunchTests

@end

@implementation FBSimulatorControlSimulatorLaunchTests

- (void)doTestLaunchesSingleSimulator
{
  FBSimulatorSession *session = [self createSession];
  XCTAssertEqual(session.state.lifecycle, FBSimulatorSessionLifecycleStateNotStarted);
  [self.assert noNotificationsToConsume];

  NSError *error = nil;
  [self.assert interactionSuccessful:session.interact.bootSimulator];
  XCTAssertEqual(session.state.lifecycle, FBSimulatorSessionLifecycleStateStarted);
  [self.assert consumeNotification:FBSimulatorSessionDidStartNotification];
  [self.assert consumeNotification:FBSimulatorSessionSimulatorProcessDidLaunchNotification];
  [self.assert noNotificationsToConsume];

  XCTAssertEqual(session.simulator.state, FBSimulatorStateBooted);
  XCTAssertEqual(session.state.runningAgents.count, 0);
  XCTAssertEqual(session.state.runningApplications.count, 0);
  XCTAssertNotEqual(session.simulator.processIdentifier, -1);
  XCTAssertNotNil(session.simulator.launchdBootstrapPath);
  XCTAssertNotNil(session.simulator.launchedProcesses);

  XCTAssertTrue([session terminateWithError:&error]);
  XCTAssertEqual(session.state.lifecycle, FBSimulatorSessionLifecycleStateEnded);
  XCTAssertEqual(session.simulator.processIdentifier, -1);
  [self.assert consumeNotification:FBSimulatorSessionSimulatorProcessDidTerminateNotification];
  [self.assert consumeNotification:FBSimulatorSessionDidEndNotification];
  [self.assert noNotificationsToConsume];
}

- (void)doTestLaunchesMultipleSimulatorsConcurrently
{
  // Simulator Pool management is single threaded since it relies on unsynchronised mutable state
  // Create the sessions in sequence, then boot them in paralell.
  __block NSError *error = nil;
  FBSimulatorSession *session1 = [self.control createSessionForSimulatorConfiguration:FBSimulatorConfiguration.iPhone5 error:&error];
  XCTAssertEqual(session1.state.lifecycle, FBSimulatorSessionLifecycleStateNotStarted);
  XCTAssertNotNil(session1);
  XCTAssertNil(error);

  FBSimulatorSession *session2 = [self.control createSessionForSimulatorConfiguration:FBSimulatorConfiguration.iPhone5 error:&error];
  XCTAssertEqual(session2.state.lifecycle, FBSimulatorSessionLifecycleStateNotStarted);
  XCTAssertNotNil(session2);
  XCTAssertNil(error);

  FBSimulatorSession *session3 = [self.control createSessionForSimulatorConfiguration:FBSimulatorConfiguration.iPad2 error:&error];
  XCTAssertEqual(session3.state.lifecycle, FBSimulatorSessionLifecycleStateNotStarted);
  XCTAssertNotNil(session3);
  XCTAssertNil(error);

  XCTAssertEqual(self.control.simulatorPool.allocatedSimulators.count, 3);
  XCTAssertEqual(([[NSSet setWithArray:@[session1.simulator.udid, session2.simulator.udid, session3.simulator.udid]] count]), 3);

  [self.assert interactionSuccessful:session1.interact.bootSimulator];
  [self.assert interactionSuccessful:session2.interact.bootSimulator];
  [self.assert interactionSuccessful:session3.interact.bootSimulator];

  NSMutableSet *simulatorPIDs = [NSMutableSet set];
  for (FBSimulatorSession *session in @[session1, session2, session3]) {
    XCTAssertEqual(session.simulator.state, FBSimulatorStateBooted);
    XCTAssertEqual(session.state.lifecycle, FBSimulatorSessionLifecycleStateStarted);
    XCTAssertEqual(session.state.runningApplications.count, 0);
    XCTAssertEqual(session.state.runningAgents.count, 0);
    XCTAssertNotEqual(session.simulator.processIdentifier, -1);

    [simulatorPIDs addObject:@(session.simulator.processIdentifier)];

    XCTAssertTrue([session terminateWithError:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(session.simulator.processIdentifier, -1);
    XCTAssertEqual(session.state.lifecycle, FBSimulatorSessionLifecycleStateEnded);
  }

  XCTAssertEqual(self.control.simulatorPool.allocatedSimulators.count, 0);
  XCTAssertEqual(simulatorPIDs.count, 3);
}

@end

@implementation FBSimulatorControlSimulatorLaunchTests_DefaultSet

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

@implementation FBSimulatorControlSimulatorLaunchTests_CustomSet

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

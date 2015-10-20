/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulator+Queries.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorApplication.h>
#import <FBSimulatorControl/FBSimulatorConfiguration.h>
#import <FBSimulatorControl/FBSimulatorControl+Private.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorControlStaticConfiguration.h>
#import <FBSimulatorControl/FBSimulatorPool.h>
#import <FBSimulatorControl/FBSimulatorSession.h>
#import <FBSimulatorControl/FBSimulatorSessionInteraction.h>
#import <FBSimulatorControl/FBSimulatorSessionLifecycle.h>
#import <FBSimulatorControl/FBSimulatorSessionState+Queries.h>
#import <FBSimulatorControl/FBSimulatorSessionState.h>

#import "FBInteractionAssertion.h"
#import "FBSimulatorControlNotificationAssertion.h"
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
  [self.notificationAssertion noNotificationsToConsume];

  NSError *error = nil;
  [self.interactionAssertion assertPerformSuccess:session.interact.bootSimulator];
  XCTAssertEqual(session.state.lifecycle, FBSimulatorSessionLifecycleStateStarted);
  [self.notificationAssertion consumeNotification:FBSimulatorSessionDidStartNotification];
  [self.notificationAssertion consumeNotification:FBSimulatorSessionSimulatorProcessDidLaunchNotification];
  [self.notificationAssertion noNotificationsToConsume];

  XCTAssertEqual(session.simulator.state, FBSimulatorStateBooted);
  XCTAssertEqual(session.state.runningAgents.count, 0);
  XCTAssertEqual(session.state.runningApplications.count, 0);
  XCTAssertNotEqual(session.simulator.processIdentifier, -1);
  XCTAssertNotNil(session.simulator.launchdBootstrapPath);
  XCTAssertNotNil(session.simulator.launchedProcesses);

  XCTAssertTrue([session terminateWithError:&error]);
  XCTAssertEqual(session.state.lifecycle, FBSimulatorSessionLifecycleStateEnded);
  XCTAssertEqual(session.simulator.processIdentifier, -1);
  [self.notificationAssertion consumeNotification:FBSimulatorSessionSimulatorProcessDidTerminateNotification];
  [self.notificationAssertion consumeNotification:FBSimulatorSessionDidEndNotification];
  [self.notificationAssertion noNotificationsToConsume];
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

  // These should fire on multiple threads at the same time. Since they don't access each other's state & DTMobile seems ok with it
  // these can be concurrent with each other. Terminating simulators returns devices to the pool, so should be sequenced.
  dispatch_group_t group = dispatch_group_create();
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

  dispatch_group_async(group, queue, ^{
    [self.interactionAssertion assertPerformSuccess:session1.interact.bootSimulator];
  });
  dispatch_group_async(group, queue, ^{
    [self.interactionAssertion assertPerformSuccess:session2.interact.bootSimulator];
  });
  dispatch_group_async(group, queue, ^{
    [self.interactionAssertion assertPerformSuccess:session3.interact.bootSimulator];
  });
  dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

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

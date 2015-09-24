/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <OCMock/OCMock.h>

#import <FBSimulatorControl/FBSimulator+Queries.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorApplication.h>
#import <FBSimulatorControl/FBSimulatorConfiguration.h>
#import <FBSimulatorControl/FBSimulatorControl+Private.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorPool.h>
#import <FBSimulatorControl/FBSimulatorSession.h>
#import <FBSimulatorControl/FBSimulatorSessionInteraction.h>
#import <FBSimulatorControl/FBSimulatorSessionLifecycle.h>
#import <FBSimulatorControl/FBSimulatorSessionState+Queries.h>
#import <FBSimulatorControl/FBSimulatorSessionState.h>
#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

#import "FBSimulatorControlNotificationAssertion.h"

@interface FBSimulatorControlSimulatorLaunchTests : XCTestCase

@property (nonatomic, strong) FBSimulatorControl *control;
@property (nonatomic, strong) FBSimulatorControlNotificationAssertion *notificationAssertion;

@end

@implementation FBSimulatorControlSimulatorLaunchTests

- (void)setUp
{
  FBSimulatorManagementOptions options =
    FBSimulatorManagementOptionsDeleteManagedSimulatorsOnFirstStart |
    FBSimulatorManagementOptionsKillUnmanagedSimulatorsOnFirstStart |
    FBSimulatorManagementOptionsDeleteOnFree;

  FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration
    configurationWithSimulatorApplication:[FBSimulatorApplication simulatorApplicationWithError:nil]
    namePrefix:nil
    bucket:0
    options:options];

  self.control = [[FBSimulatorControl alloc] initWithConfiguration:configuration];
  self.notificationAssertion = [FBSimulatorControlNotificationAssertion new];
}

- (void)tearDown
{
  [self.control.simulatorPool killManagedSimulatorsWithError:nil];
  self.control = nil;
}

- (void)testLaunchesSingleSimulator
{
  NSError *error = nil;
  FBSimulatorSession *session = [self.control createSessionForSimulatorConfiguration:FBSimulatorConfiguration.iPhone5 error:&error];
  XCTAssertEqual(session.state.lifecycle, FBSimulatorSessionLifecycleStateNotStarted);
  XCTAssertNotNil(session);
  XCTAssertNil(error);
  [self.notificationAssertion noNotificationsToConsume];

  BOOL success = [[session.interact bootSimulator] performInteractionWithError:&error];
  XCTAssertTrue(success);
  XCTAssertEqual(session.state.lifecycle, FBSimulatorSessionLifecycleStateStarted);
  XCTAssertNil(error);
  [self.notificationAssertion consumeNotification:FBSimulatorSessionDidStartNotification];
  [self.notificationAssertion consumeNotification:FBSimulatorSessionSimulatorProcessDidLaunchNotification];
  [self.notificationAssertion noNotificationsToConsume];

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

- (void)testLaunchesMultipleSimulatorsConcurrently
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

  __block NSError *error1 = nil;
  __block BOOL launchSuccess1 = NO;
  __block NSError *error2 = nil;
  __block BOOL launchSuccess2 = NO;
  __block NSError *error3 = nil;
  __block BOOL launchSuccess3 = NO;

  // These should fire on multiple threads at the same time. Since they don't access each other's state & DTMobile seems ok with it
  // these can be concurrent with each other. Terminating simulators returns devices to the pool, so should be sequenced.
  dispatch_group_t group = dispatch_group_create();
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

  dispatch_group_async(group, queue, ^{
    launchSuccess1 = [[session1.interact bootSimulator] performInteractionWithError:&error1];
  });
  dispatch_group_async(group, queue, ^{
    launchSuccess2 = [[session2.interact bootSimulator] performInteractionWithError:&error2];
  });
  dispatch_group_async(group, queue, ^{
    launchSuccess3 = [[session3.interact bootSimulator] performInteractionWithError:&error3];
  });
  dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

  XCTAssertTrue(launchSuccess1);
  XCTAssertTrue(launchSuccess2);
  XCTAssertTrue(launchSuccess3);
  XCTAssertNil(error1);
  XCTAssertNil(error2);
  XCTAssertNil(error3);

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

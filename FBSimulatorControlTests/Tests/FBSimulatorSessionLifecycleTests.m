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
#import "FBSimulatorControlFixtures.h"

@interface FBSimulatorSessionLifecycleTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorSessionLifecycleTests

- (void)testNotifiedByUnexpectedApplicationTermination
{
  FBSimulatorSession *session = [self createSession];
  FBApplicationLaunchConfiguration *appLaunch = self.safariAppLaunch;

  [self.assert interactionSuccessful:[session.interact.bootSimulator launchApplication:appLaunch]];

  FBUserLaunchedProcess *process = [session.state runningProcessForApplication:appLaunch.application];
  XCTAssertNotNil(process);
  if (!process) {
    // Need to guard against continuing the test in case the PID is 0 or -1 to avoid nuking the machine.
    return;
  }

  __block BOOL notificationRecieved = NO;
  __block BOOL wasUnexpected = NO;

  id token = [NSNotificationCenter.defaultCenter
    addObserverForName:FBSimulatorSessionApplicationProcessDidTerminateNotification
    object:session
    queue:NSOperationQueue.mainQueue
    usingBlock:^(NSNotification *notification) {
      notificationRecieved = YES;
      wasUnexpected = ![notification.userInfo[FBSimulatorSessionExpectedKey] boolValue];
    }];

  XCTAssertEqual(kill((pid_t)process.processIdentifier, SIGKILL), 0);

  BOOL didMeetConditionBeforeTimeout = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:10 untilTrue:^ BOOL {
    return notificationRecieved == YES;
  }];

  XCTAssertTrue(didMeetConditionBeforeTimeout);
  XCTAssertTrue(wasUnexpected);
  [NSNotificationCenter.defaultCenter removeObserver:token];

  XCTAssertFalse([session.state runningProcessForApplication:appLaunch.application]);
}

- (void)testNotifiedByExpectedApplicationTermination
{
  FBSimulatorSession *session = [self createSession];
  FBApplicationLaunchConfiguration *appLaunch = self.safariAppLaunch;

  [self.assert interactionSuccessful:[session.interact.bootSimulator launchApplication:appLaunch]];

  FBUserLaunchedProcess *process = [session.state runningProcessForApplication:appLaunch.application];
  XCTAssertNotNil(process);
  if (!process) {
    // Need to guard against continuing the test in case the PID is 0 or -1 to avoid nuking the machine.
    return;
  }

  __block BOOL notificationRecieved = NO;
  __block BOOL wasExpected = NO;

  id token = [NSNotificationCenter.defaultCenter
    addObserverForName:FBSimulatorSessionApplicationProcessDidTerminateNotification
    object:session
    queue:NSOperationQueue.mainQueue
    usingBlock:^(NSNotification *notification) {
      notificationRecieved = YES;
      wasExpected = [notification.userInfo[FBSimulatorSessionExpectedKey] boolValue];
    }];

  [self.assert interactionSuccessful:[session.interact killApplication:appLaunch.application]];

  BOOL didMeetConditionBeforeTimeout = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:10 untilTrue:^ BOOL {
    return notificationRecieved == YES;
  }];

  XCTAssertTrue(didMeetConditionBeforeTimeout);
  XCTAssertTrue(wasExpected);
  [NSNotificationCenter.defaultCenter removeObserver:token];

  XCTAssertFalse([session.state runningProcessForApplication:appLaunch.application]);
}


@end

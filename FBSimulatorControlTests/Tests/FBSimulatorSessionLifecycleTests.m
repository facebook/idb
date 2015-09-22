/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBProcessLaunchConfiguration.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorApplication.h>
#import <FBSimulatorControl/FBSimulatorConfiguration.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBSimulatorControl/FBSimulatorControl+Private.h>
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorProcess.h>
#import <FBSimulatorControl/FBSimulatorSession.h>
#import <FBSimulatorControl/FBSimulatorSessionInteraction.h>
#import <FBSimulatorControl/FBSimulatorSessionLifecycle.h>
#import <FBSimulatorControl/FBSimulatorSessionState.h>
#import <FBSimulatorControl/FBSimulatorSessionState+Queries.h>
#import <FBSimulatorControl/NSRunLoop+SimulatorControlAdditions.h>

@interface FBSimulatorSessionLifecycleTests : XCTestCase

@property (nonatomic, strong) FBSimulatorControl *control;

@end

@implementation FBSimulatorSessionLifecycleTests

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
}

- (void)testNotifiedByUnexpectedApplicationTermination
{
  NSError *error = nil;
  FBSimulatorSession *session = [self.control createSessionForSimulatorConfiguration:FBSimulatorConfiguration.iPhone5 error:&error];

  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithApplication:[FBSimulatorApplication systemApplicationNamed:@"MobileSafari"]
    arguments:@[]
    environment:@{}];

  BOOL success = [[[session.interact
    bootSimulator]
    launchApplication:appLaunch]
    performInteractionWithError:&error];

  XCTAssertTrue(success);
  XCTAssertNil(error);

  FBUserLaunchedProcess *process = [session.state processForApplication:appLaunch.application];
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

  XCTAssertFalse([session.state processForApplication:appLaunch.application]);
}

- (void)testNotifiedByExpectedApplicationTermination
{
  NSError *error = nil;
  FBSimulatorSession *session = [self.control createSessionForSimulatorConfiguration:FBSimulatorConfiguration.iPhone5 error:&error];

  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithApplication:[FBSimulatorApplication systemApplicationNamed:@"MobileSafari"]
    arguments:@[]
    environment:@{}];

  BOOL success = [[[session.interact
    bootSimulator]
    launchApplication:appLaunch]
    performInteractionWithError:&error];

  XCTAssertTrue(success);
  XCTAssertNil(error);

  FBUserLaunchedProcess *process = [session.state processForApplication:appLaunch.application];
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

  XCTAssertTrue([[session.interact killApplication:appLaunch.application] performInteractionWithError:&error]);
  XCTAssertNil(error);

  BOOL didMeetConditionBeforeTimeout = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:10 untilTrue:^ BOOL {
    return notificationRecieved == YES;
  }];

  XCTAssertTrue(didMeetConditionBeforeTimeout);
  XCTAssertTrue(wasExpected);
  [NSNotificationCenter.defaultCenter removeObserver:token];

  XCTAssertFalse([session.state processForApplication:appLaunch.application]);
}


@end

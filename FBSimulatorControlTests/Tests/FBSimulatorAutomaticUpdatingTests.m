/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <AppKit/AppKit.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBSimulatorControlAssertions.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorAutomaticUpdatingTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorAutomaticUpdatingTests

- (void)setUp
{
  [super setUp];
}

- (void)testGetsArgumentsOfSimulatorContainerProcess
{
  FBSimulatorSession *session = [self createBootedSession];
  FBSimulator *simulator = session.simulator;

  FBProcessInfo *containerProcess = simulator.containerApplication;
  XCTAssertNotNil(containerProcess);

  NSSet *arguments = [NSSet setWithArray:containerProcess.arguments];
  XCTAssertTrue([arguments containsObject:session.simulator.udid]);
}

- (void)testUpdatesContainerProcessOnTermination
{
  FBSimulatorSession *session = [self createBootedSession];
  FBSimulator *simulator = session.simulator;

  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBSimulatorControlGlobalConfiguration.fastTimeout untilTrue:^{
    return NO;
  }];

  FBProcessInfo *containerApplication = simulator.containerApplication;
  XCTAssertNotNil(containerApplication);

  NSRunningApplication *workspaceApplication = [simulator.processQuery runningApplicationForProcess:containerApplication];
  XCTAssertNotNil(workspaceApplication);
  [workspaceApplication forceTerminate];

  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBSimulatorControlGlobalConfiguration.fastTimeout untilTrue:^BOOL{
    return NO;
  }];

  XCTAssertNil(simulator.containerApplication);
}

- (void)testNotifiedByUnexpectedApplicationTermination
{
  if (FBSimulatorControlTestCase.isRunningOnTravis) {
    return;
  }

  FBSimulatorSession *session = [self createSession];

  [self assertInteractionSuccessful:[session.interact.bootSimulator launchApplication:self.safariAppLaunch]];

  FBProcessInfo *process = [session.history runningProcessForApplication:self.safariApplication];
  XCTAssertNotNil(process);
  if (!process) {
    // Need to guard against continuing the test in case the PID is 0 or -1 to avoid nuking the machine.
    return;
  }

  [self.assert consumeAllNotifications];
  XCTAssertEqual(kill((pid_t)process.processIdentifier, SIGKILL), 0);

  NSNotification *actual = [self.assert consumeNotification:FBSimulatorApplicationProcessDidTerminateNotification timeout:20];
  XCTAssertFalse([actual.userInfo[FBSimulatorExpectedTerminationKey] boolValue]);
  XCTAssertNil([session.history runningProcessForApplication:self.safariApplication]);
}

- (void)testNotifiedByExpectedApplicationTermination
{
  if (FBSimulatorControlTestCase.isRunningOnTravis) {
    return;
  }

  FBSimulatorSession *session = [self createSession];
  FBApplicationLaunchConfiguration *appLaunch = self.safariAppLaunch;

  [self assertInteractionSuccessful:[session.interact.bootSimulator launchApplication:appLaunch]];

  FBProcessInfo *process = [session.history runningProcessForApplication:self.safariApplication];
  XCTAssertNotNil(process);
  if (!process) {
    // Need to guard against continuing the test in case the PID is 0 or -1 to avoid nuking the machine.
    return;
  }

  [self.assert consumeAllNotifications];
  [self assertInteractionSuccessful:[session.interact killProcess:process]];

  NSNotification *actual = [self.assert consumeNotification:FBSimulatorApplicationProcessDidTerminateNotification timeout:20];
  XCTAssertTrue([actual.userInfo[FBSimulatorExpectedTerminationKey] boolValue]);
  XCTAssertNil([session.history runningProcessForApplication:self.safariApplication]);
}

@end

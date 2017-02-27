/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <Cocoa/Cocoa.h>

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
  // Test only relevant for Simulator.app Launching
  if (FBSimulatorControlTestCase.useDirectLaunching) {
    return;
  }

  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  FBProcessInfo *containerProcess = simulator.containerApplication;
  XCTAssertNotNil(containerProcess);

  NSSet *arguments = [NSSet setWithArray:containerProcess.arguments];
  XCTAssertTrue([arguments containsObject:simulator.udid]);
}

- (void)testUpdatesContainerProcessOnTermination
{
  // Test only relevant for Simulator.app Launching
  if (FBSimulatorControlTestCase.useDirectLaunching) {
    return;
  }

  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  FBProcessInfo *containerApplication = simulator.containerApplication;
  XCTAssertNotNil(containerApplication);

  NSRunningApplication *workspaceApplication = [simulator.processFetcher.processFetcher runningApplicationForProcess:containerApplication];
  XCTAssertNotNil(workspaceApplication);
  [workspaceApplication forceTerminate];

  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilTrue:^BOOL{
    return NO;
  }];

  XCTAssertNil(simulator.containerApplication);
}

- (void)testNotifiedByUnexpectedApplicationTermination
{
  if (FBSimulatorControlTestCase.isRunningOnTravis) {
    return;
  }

  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  FBApplicationLaunchConfiguration *appLaunch = self.safariAppLaunch;
  NSError *error = nil;
  BOOL success = [simulator launchApplication:appLaunch error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  FBProcessInfo *process = [simulator.history runningProcessForApplication:self.safariApplication];
  XCTAssertNotNil(process);
  if (!process) {
    // Need to guard against continuing the test in case the PID is 0 or -1 to avoid nuking the machine.
    return;
  }

  [self.assert consumeAllNotifications];
  XCTAssertEqual(kill((pid_t)process.processIdentifier, SIGKILL), 0);

  NSNotification *actual = [self.assert consumeNotification:FBSimulatorNotificationNameApplicationProcessDidTerminate timeout:20];
  XCTAssertFalse([actual.userInfo[FBSimulatorNotificationUserInfoKeyExpectedTermination] boolValue]);
  XCTAssertNil([simulator.history runningProcessForApplication:self.safariApplication]);
}

- (void)testNotifiedByExpectedApplicationTermination
{
  if (FBSimulatorControlTestCase.isRunningOnTravis) {
    return;
  }

  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  FBApplicationLaunchConfiguration *appLaunch = self.safariAppLaunch;
  NSError *error = nil;
  BOOL success = [simulator launchApplication:appLaunch error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  FBProcessInfo *process = [simulator.history runningProcessForApplication:self.safariApplication];
  XCTAssertNotNil(process);
  if (!process) {
    // Need to guard against continuing the test in case the PID is 0 or -1 to avoid nuking the machine.
    return;
  }

  [self.assert consumeAllNotifications];
  success = [simulator terminateSubprocess:process error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  NSNotification *actual = [self.assert consumeNotification:FBSimulatorNotificationNameApplicationProcessDidTerminate timeout:20];
  XCTAssertTrue([actual.userInfo[FBSimulatorNotificationUserInfoKeyExpectedTermination] boolValue]);
  XCTAssertNil([simulator.history runningProcessForApplication:self.safariApplication]);
}

@end

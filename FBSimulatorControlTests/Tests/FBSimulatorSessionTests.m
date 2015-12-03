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

@interface FBSimulatorSessionTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorSessionTests

- (void)testNotifiedByUnexpectedApplicationTermination
{
  FBSimulatorSession *session = [self createSession];
  FBApplicationLaunchConfiguration *appLaunch = self.safariAppLaunch;

  [self.assert interactionSuccessful:[session.interact.bootSimulator launchApplication:appLaunch]];

  FBProcessInfo *process = [session.history runningProcessForApplication:appLaunch.application];
  XCTAssertNotNil(process);
  if (!process) {
    // Need to guard against continuing the test in case the PID is 0 or -1 to avoid nuking the machine.
    return;
  }

  [self.assert consumeAllNotifications];
  XCTAssertEqual(kill((pid_t)process.processIdentifier, SIGKILL), 0);

  NSNotification *actual = [self.assert consumeNotification:FBSimulatorApplicationProcessDidTerminateNotification timeout:20];
  XCTAssertFalse([actual.userInfo[FBSimulatorExpectedTerminationKey] boolValue]);
  XCTAssertNil([session.history runningProcessForApplication:appLaunch.application]);
}

- (void)testNotifiedByExpectedApplicationTermination
{
  FBSimulatorSession *session = [self createSession];
  FBApplicationLaunchConfiguration *appLaunch = self.safariAppLaunch;

  [self.assert interactionSuccessful:[session.interact.bootSimulator launchApplication:appLaunch]];

  FBProcessInfo *process = [session.history runningProcessForApplication:appLaunch.application];
  XCTAssertNotNil(process);
  if (!process) {
    // Need to guard against continuing the test in case the PID is 0 or -1 to avoid nuking the machine.
    return;
  }

  [self.assert consumeAllNotifications];
  [self.assert interactionSuccessful:[session.interact killApplication:appLaunch.application]];

  NSNotification *actual = [self.assert consumeNotification:FBSimulatorApplicationProcessDidTerminateNotification timeout:20];
  XCTAssertTrue([actual.userInfo[FBSimulatorExpectedTerminationKey] boolValue]);
  XCTAssertNil([session.history runningProcessForApplication:appLaunch.application]);
}

@end

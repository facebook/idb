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

@interface FBSimulatorControlApplicationLaunchTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorControlApplicationLaunchTests

- (void)testLaunchesSafariApplication
{
  FBSimulatorSession *session = [self createSession];

  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithApplication:self.safariApplication
    arguments:@[]
    environment:@{}];

  [self.assert interactionSuccessful:[session.interact.bootSimulator launchApplication:appLaunch]];

  [self.assert consumeNotification:FBSimulatorSessionDidStartNotification];
  [self.assert consumeNotification:FBSimulatorDidLaunchNotification];
  [self.assert consumeNotification:FBSimulatorSessionApplicationProcessDidLaunchNotification];
  [self.assert noNotificationsToConsume];
}

- (void)testLaunchesSampleApplication
{
  FBSimulatorSession *session = [self createSession];
  FBApplicationLaunchConfiguration *appLaunch = self.tableSearchAppLaunch;

  [self.assert interactionSuccessful:[[[session.interact
    bootSimulator]
    installApplication:appLaunch.application]
    launchApplication:appLaunch]];

  [self.assert consumeNotification:FBSimulatorSessionDidStartNotification];
  [self.assert consumeNotification:FBSimulatorDidLaunchNotification];
  [self.assert consumeNotification:FBSimulatorSessionApplicationProcessDidLaunchNotification];
  [self.assert noNotificationsToConsume];
}

@end

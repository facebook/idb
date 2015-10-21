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
#import <FBSimulatorControl/FBSimulatorControl+Private.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorPool.h>
#import <FBSimulatorControl/FBSimulatorSession.h>
#import <FBSimulatorControl/FBSimulatorSessionInteraction.h>
#import <FBSimulatorControl/FBSimulatorSessionLifecycle.h>

#import "FBInteractionAssertion.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlNotificationAssertion.h"
#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorControlApplicationLaunchTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorControlApplicationLaunchTests

- (void)testLaunchesSafariApplication
{
  FBSimulatorSession *session = [self createSession];

  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithApplication:[FBSimulatorApplication systemApplicationNamed:@"MobileSafari"]
    arguments:@[]
    environment:@{}];

  [self.interactionAssertion assertPerformSuccess:[session.interact.bootSimulator launchApplication:appLaunch]];

  [self.notificationAssertion consumeNotification:FBSimulatorSessionDidStartNotification];
  [self.notificationAssertion consumeNotification:FBSimulatorSessionSimulatorProcessDidLaunchNotification];
  [self.notificationAssertion consumeNotification:FBSimulatorSessionApplicationProcessDidLaunchNotification];
  [self.notificationAssertion noNotificationsToConsume];
}

- (void)testLaunchesSampleApplication
{
  FBSimulatorSession *session = [self createSession];

  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithApplication:[FBSimulatorControlFixtures tableSearchApplicationWithError:nil]
    arguments:@[]
    environment:@{}];

  [self.interactionAssertion assertPerformSuccess:[[[session.interact
    bootSimulator]
    installApplication:appLaunch.application]
    launchApplication:appLaunch]];

  [self.notificationAssertion consumeNotification:FBSimulatorSessionDidStartNotification];
  [self.notificationAssertion consumeNotification:FBSimulatorSessionSimulatorProcessDidLaunchNotification];
  [self.notificationAssertion consumeNotification:FBSimulatorSessionApplicationProcessDidLaunchNotification];
  [self.notificationAssertion noNotificationsToConsume];
}


@end

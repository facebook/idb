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

#import "FBSimulatorControlAssertions.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlAssertions.h"
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

  [self.assert interactionSuccessful:[session.interact.bootSimulator launchApplication:appLaunch]];

  [self.assert consumeNotification:FBSimulatorSessionDidStartNotification];
  [self.assert consumeNotification:FBSimulatorSessionSimulatorProcessDidLaunchNotification];
  [self.assert consumeNotification:FBSimulatorSessionApplicationProcessDidLaunchNotification];
  [self.assert noNotificationsToConsume];
}

- (void)testLaunchesSampleApplication
{
  FBSimulatorSession *session = [self createSession];

  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithApplication:[FBSimulatorControlFixtures tableSearchApplicationWithError:nil]
    arguments:@[]
    environment:@{}];

  [self.assert interactionSuccessful:[[[session.interact
    bootSimulator]
    installApplication:appLaunch.application]
    launchApplication:appLaunch]];

  [self.assert consumeNotification:FBSimulatorSessionDidStartNotification];
  [self.assert consumeNotification:FBSimulatorSessionSimulatorProcessDidLaunchNotification];
  [self.assert consumeNotification:FBSimulatorSessionApplicationProcessDidLaunchNotification];
  [self.assert noNotificationsToConsume];
}


@end

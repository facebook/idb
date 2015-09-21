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
#import <FBSimulatorControl/FBSimulatorSessionState+Queries.h>
#import <FBSimulatorControl/FBSimulatorSessionState.h>
#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

#import "FBSimulatorControlNotificationAssertion.h"

@interface FBSimulatorControlApplicationLaunchTests : XCTestCase

@property (nonatomic, strong) FBSimulatorControl *control;
@property (nonatomic, strong) FBSimulatorControlNotificationAssertion *notificationAssertion;

@end

@implementation FBSimulatorControlApplicationLaunchTests

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

- (void)testLaunchesSafariApplication
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
  [self.notificationAssertion consumeNotification:FBSimulatorSessionDidStartNotification];
  [self.notificationAssertion consumeNotification:FBSimulatorSessionSimulatorProcessDidLaunchNotification];
  [self.notificationAssertion consumeNotification:FBSimulatorSessionApplicationProcessDidLaunchNotification];
  [self.notificationAssertion noNotificationsToConsume];
}

@end

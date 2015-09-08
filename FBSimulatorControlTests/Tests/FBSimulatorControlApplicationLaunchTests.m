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

#import "FBProcessLaunchConfiguration.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl+Private.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSession.h"
#import "FBSimulatorSessionInteraction.h"
#import "FBSimulatorSessionLifecycle.h"
#import "FBSimulatorSessionState+Queries.h"
#import "FBSimulatorSessionState.h"
#import "SimDevice.h"
#import "SimDeviceSet.h"

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

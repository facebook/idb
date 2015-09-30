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

#import <FBSimulatorControl/FBSimulator+Queries.h>
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
#import <FBSimulatorControl/FBSimulatorWindowTiler.h>
#import <FBSimulatorControl/FBSimulatorWindowTilingStrategy.h>

@interface FBSimulatorWindowTilingTests : XCTestCase

@property (nonatomic, strong) FBSimulatorControl *control;

@end

@implementation FBSimulatorWindowTilingTests

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

- (void)testTilesSingleiPhoneSimulatorInTopLeft
{
  // Approval is required externally to the Test Runner. Without approval, the tests can't run
  if (!AXIsProcessTrusted()) {
    NSLog(@"%@ can't run as the host process isn't trusted", NSStringFromSelector(_cmd));
    return;
  }

  NSError *error = nil;
  FBSimulatorSession *session = [self.control createSessionForSimulatorConfiguration:FBSimulatorConfiguration.iPhone5 error:&error];
  XCTAssertNotNil(session);
  XCTAssertNil(error);

  BOOL success = [[session.interact
    bootSimulator]
    performInteractionWithError:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  FBSimulatorWindowTiler *tiler = [FBSimulatorWindowTiler
    withSimulator:session.simulator
    strategy:[FBSimulatorWindowTilingStrategy horizontalOcclusionStrategy:session.simulator]];
  CGRect position = [tiler placeInForegroundWithError:&error];
  XCTAssertNil(error);
  XCTAssertEqual(CGRectGetMinX(position), 0);
  XCTAssertEqual(CGRectGetMinX(position), 0);
}

- (void)disabled_testTilesMultipleiPhones5Horizontally
{
  // Approval is required externally to the Test Runner. Without approval, the tests can't run
  if (!AXIsProcessTrusted()) {
    NSLog(@"%@ can't run as the host process isn't trusted", NSStringFromSelector(_cmd));
    return;
  }

  FBSimulatorConfiguration *configuration = FBSimulatorConfiguration.iPhone5.scale50Percent;
  CGFloat scaleFactor = NSScreen.mainScreen.backingScaleFactor;

  NSError *error = nil;
  FBSimulatorSession *firstSession = [self.control createSessionForSimulatorConfiguration:configuration error:&error];
  XCTAssertNotNil(firstSession);
  XCTAssertNil(error);

  BOOL success = [[firstSession.interact
    bootSimulator]
    performInteractionWithError:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  FBSimulatorWindowTiler *tiler = [FBSimulatorWindowTiler
    withSimulator:firstSession.simulator
    strategy:[FBSimulatorWindowTilingStrategy horizontalOcclusionStrategy:firstSession.simulator]];
  CGRect position = [tiler placeInForegroundWithError:&error];
  XCTAssertNil(error);
  XCTAssertEqual(CGRectGetMinX(position), 0);
  XCTAssertEqual(CGRectGetMinY(position), 0);

  FBSimulatorSession *secondSession = [self.control createSessionForSimulatorConfiguration:configuration error:&error];
  XCTAssertNotNil(secondSession);
  XCTAssertNil(error);

  success = [[secondSession.interact
    bootSimulator]
    performInteractionWithError:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  tiler = [FBSimulatorWindowTiler
    withSimulator:secondSession.simulator
    strategy:[FBSimulatorWindowTilingStrategy horizontalOcclusionStrategy:secondSession.simulator]];
  position = [tiler placeInForegroundWithError:&error];
  XCTAssertNil(error);
  XCTAssertEqual(CGRectGetMinX(position), 320 / scaleFactor);
  XCTAssertEqual(CGRectGetMinY(position), 0);

  FBSimulatorSession *thirdSession = [self.control createSessionForSimulatorConfiguration:configuration error:&error];
  XCTAssertNotNil(thirdSession);
  XCTAssertNil(error);

  success = [[thirdSession.interact
    bootSimulator]
    performInteractionWithError:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  tiler = [FBSimulatorWindowTiler
    withSimulator:thirdSession.simulator
    strategy:[FBSimulatorWindowTilingStrategy horizontalOcclusionStrategy:thirdSession.simulator]];
  position = [tiler placeInForegroundWithError:&error];
  XCTAssertNil(error);
  XCTAssertEqual(CGRectGetMinX(position), 640 / scaleFactor);
  XCTAssertEqual(CGRectGetMinY(position), 0);
}

@end

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

#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorWindowTilingTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorWindowTilingTests

- (FBSimulatorConfiguration *)simulatorConfiguration
{
  return FBSimulatorConfiguration.iPhone5.scale50Percent;
}

- (void)testTilesSingleiPhoneSimulatorInTopLeft
{
  // Approval is required externally to the Test Runner. Without approval, the tests can't run
  if (!AXIsProcessTrusted()) {
    NSLog(@"%@ can't run as the host process isn't trusted", NSStringFromSelector(_cmd));
    return;
  }

  FBSimulatorSession *session = [self createBootedSession];
  FBSimulatorWindowTiler *tiler = [FBSimulatorWindowTiler
    withSimulator:session.simulator
    strategy:[FBSimulatorWindowTilingStrategy horizontalOcclusionStrategy:session.simulator]];

  NSError *error = nil;
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
  CGFloat scaleFactor = NSScreen.mainScreen.backingScaleFactor;

  FBSimulatorSession *firstSession = [self createBootedSession];
  FBSimulatorWindowTiler *tiler = [FBSimulatorWindowTiler
    withSimulator:firstSession.simulator
    strategy:[FBSimulatorWindowTilingStrategy horizontalOcclusionStrategy:firstSession.simulator]];
  NSError *error = nil;
  CGRect position = [tiler placeInForegroundWithError:&error];
  XCTAssertNil(error);
  XCTAssertEqual(CGRectGetMinX(position), 0);
  XCTAssertEqual(CGRectGetMinY(position), 0);

  FBSimulatorSession *secondSession = [self createBootedSession];
  tiler = [FBSimulatorWindowTiler
    withSimulator:secondSession.simulator
    strategy:[FBSimulatorWindowTilingStrategy horizontalOcclusionStrategy:secondSession.simulator]];
  position = [tiler placeInForegroundWithError:&error];
  XCTAssertNil(error);
  XCTAssertEqual(CGRectGetMinX(position), 320 / scaleFactor);
  XCTAssertEqual(CGRectGetMinY(position), 0);

  FBSimulatorSession *thirdSession = [self createBootedSession];
  XCTAssertNotNil(thirdSession);
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

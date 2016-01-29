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

- (void)testTilesSingleiPhoneSimulatorInTopLeft
{
  // Approval is required externally to the Test Runner. Without approval, the tests can't run
  if (!AXIsProcessTrusted()) {
    NSLog(@"%@ can't run as the host process isn't trusted", NSStringFromSelector(_cmd));
    return;
  }

  FBSimulator *simulator = [self obtainBootedSimulator];
  FBSimulatorWindowTiler *tiler = [FBSimulatorWindowTiler
    withSimulator:simulator
    strategy:[FBSimulatorWindowTilingStrategy horizontalOcclusionStrategy:simulator]];

  NSError *error = nil;
  CGRect position = [tiler placeInForegroundWithError:&error];
  XCTAssertNil(error);
  XCTAssertEqual(CGRectGetMinX(position), 0);
  XCTAssertEqual(CGRectGetMinX(position), 0);
}

@end

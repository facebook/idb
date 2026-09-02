/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/AccessibilityService+Testing.h>

@interface AccessibilityServiceServerTests : XCTestCase
@end

@implementation AccessibilityServiceServerTests

- (void)testServeBacklogAccommodatesConcurrentProbes
{
  XCTAssertEqual(FBAXBridgeServeBacklogForTesting(), 16);
}

- (void)testExitOnDisconnectIsOffUnlessAsked
{
  XCTAssertFalse(FBAXBridgeExitOnDisconnectForTesting(@[]));
  XCTAssertFalse(FBAXBridgeExitOnDisconnectForTesting(@[@"--idle-timeout", @"30"]));
}

- (void)testExitOnDisconnectIsHonouredWhenAsked
{
  XCTAssertTrue(FBAXBridgeExitOnDisconnectForTesting(@[@"--exit-on-disconnect", @"1"]));
  XCTAssertTrue(FBAXBridgeExitOnDisconnectForTesting(@[@"--idle-timeout", @"30", @"--exit-on-disconnect", @"1"]));
}

- (void)testExitOnDisconnectCanBeTurnedOffExplicitly
{
  XCTAssertFalse(FBAXBridgeExitOnDisconnectForTesting(@[@"--exit-on-disconnect", @"0"]));
}

- (void)testAnIdleTimeoutOnTheCommandLineIsHonoured
{
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[@"--idle-timeout", @"45"], 300), 45);
}

- (void)testAServeWithNoIdleTimeoutUsesTheDefault
{
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[], 300), 300);
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[@"--something-else", @"1"], 300), 300);
  XCTAssertEqual(FBAXBridgeDefaultIdleTimeoutForTesting(), 300);
}

- (void)testAnUnusableIdleTimeoutFallsBackToTheDefault
{
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[@"--idle-timeout", @"0"], 300), 300);
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[@"--idle-timeout", @"-5"], 300), 300);
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[@"--idle-timeout", @"soon"], 300), 300);
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[@"--idle-timeout", @"12x"], 300), 300);
  XCTAssertEqual(FBAXBridgeIdleTimeoutForTesting(@[@"--idle-timeout"], 300), 300);
}

@end

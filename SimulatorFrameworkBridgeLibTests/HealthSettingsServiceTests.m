/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/HealthSettingsService.h>

// Matches the existing XCTest pattern used by every other *ServiceTests.m
// file in this directory.
// ast-grep-ignore: swift-testing/objcpp/no-new-xctest
@interface HealthSettingsServiceTests : XCTestCase
@end

@implementation HealthSettingsServiceTests

// HealthKit.framework is not available on macOS, so loadAuthStore()
// returns nil and every action returns 1. These tests verify the
// error path when HealthKit is unavailable.

- (void)testListReturnsFailureWhenFrameworkUnavailable
{
  XCTAssertEqual(handleHealthSettingsAction(@"list", @"com.example.test", @[]), 1);
}

- (void)testClearReturnsFailureWhenFrameworkUnavailable
{
  XCTAssertEqual(handleHealthSettingsAction(@"clear", @"com.example.test", @[]), 1);
}

- (void)testUnknownActionReturnsFailure
{
  XCTAssertEqual(handleHealthSettingsAction(@"frobnicate", @"com.example.test", @[]), 1);
}

@end

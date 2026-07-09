/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/NotificationSettingsService.h>

@interface NotificationSettingsServiceTests : XCTestCase
@end

@implementation NotificationSettingsServiceTests

// BulletinBoard.framework is not available on macOS, so loadGateway()
// returns nil and all actions return 1. These tests verify the error path
// when the gateway is unavailable.

- (void)testApproveReturnsFailureWhenGatewayUnavailable
{
  XCTAssertEqual(handleNotificationSettingsAction(@"approve", @"com.example.test"), 1);
}

- (void)testRevokeReturnsFailureWhenGatewayUnavailable
{
  XCTAssertEqual(handleNotificationSettingsAction(@"revoke", @"com.example.test"), 1);
}

- (void)testCheckReturnsFailureWhenGatewayUnavailable
{
  XCTAssertEqual(handleNotificationSettingsAction(@"check", @"com.example.test"), 1);
}

- (void)testListReturnsFailureWhenGatewayUnavailable
{
  XCTAssertEqual(handleNotificationSettingsAction(@"list", nil), 1);
}

@end

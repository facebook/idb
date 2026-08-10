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

// BulletinBoard is present in the simulator, so every action reaches a real BBSettingsGateway.
// `approve` on an unknown section ID is still a success: the service creates a default section
// info rather than requiring the app to have launched and asked for authorization first.

- (void)testApproveSucceeds
{
  XCTAssertEqual(handleNotificationSettingsAction(@"approve", @"com.example.test"), 0);
}

- (void)testRevokeSucceeds
{
  XCTAssertEqual(handleNotificationSettingsAction(@"revoke", @"com.example.test"), 0);
}

- (void)testCheckSucceeds
{
  XCTAssertEqual(handleNotificationSettingsAction(@"check", @"com.example.test"), 0);
}

- (void)testListWithoutABundleIDSucceeds
{
  XCTAssertEqual(handleNotificationSettingsAction(@"list", nil), 0);
}

- (void)testUnknownActionReturnsFailure
{
  XCTAssertEqual(handleNotificationSettingsAction(@"frobnicate", @"com.example.test"), 1);
}

@end

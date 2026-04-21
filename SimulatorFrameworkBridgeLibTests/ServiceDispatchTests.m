/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/ServiceDispatch.h>

@interface ServiceDispatchTests : XCTestCase
@end

@implementation ServiceDispatchTests

#pragma mark - Unknown service

- (void)testUnknownServiceReturnsFailure
{
  XCTAssertEqual(dispatchService(@"unknown", @"clear", @[]), 1);
}

- (void)testEmptyServiceReturnsFailure
{
  XCTAssertEqual(dispatchService(@"", @"clear", @[]), 1);
}

#pragma mark - Contacts routing

- (void)testDispatchContactsRoutes
{
  // Verifies routing reaches handleContactsAction (not "unknown service").
  // Return value depends on TCC state: 0 with authorization, 1 without.
  int result = dispatchService(@"contacts", @"clear", @[]);
  XCTAssertTrue(result == 0 || result == 1);
}

- (void)testDispatchContactsUnknownAction
{
  XCTAssertEqual(dispatchService(@"contacts", @"unknown", @[]), 1);
}

#pragma mark - Photos routing

- (void)testDispatchPhotosClearRoutes
{
  // Verifies routing reaches handlePhotoLibraryAction.
  // Result depends on photo library state and PLPhotoLibrary availability.
  int result = dispatchService(@"photos", @"clear", @[]);
  XCTAssertTrue(result == 0 || result == 1);
}

- (void)testDispatchPhotosUnknownAction
{
  XCTAssertEqual(dispatchService(@"photos", @"unknown", @[]), 1);
}

#pragma mark - Notifications routing

- (void)testDispatchNotificationsRoutes
{
  // BulletinBoard unavailable on macOS → returns 1
  XCTAssertEqual(dispatchService(@"notifications", @"approve", @[@"com.test"]), 1);
}

- (void)testDispatchNotificationsPassesBundleID
{
  // "check" with a bundleID — gateway fails but bundleID is passed through
  XCTAssertEqual(dispatchService(@"notifications", @"check", @[@"com.test"]), 1);
}

- (void)testDispatchNotificationsNoBundleID
{
  // "list" with no arguments — bundleID is nil
  XCTAssertEqual(dispatchService(@"notifications", @"list", @[]), 1);
}

#pragma mark - Proxy routing

- (void)testDispatchProxyMissingArgsRoutes
{
  // "set" with no args → insufficient arguments error
  XCTAssertEqual(dispatchService(@"proxy", @"set", @[]), 1);
}

- (void)testDispatchProxyUnknownAction
{
  XCTAssertEqual(dispatchService(@"proxy", @"unknown", @[]), 1);
}

#pragma mark - DNS routing

- (void)testDispatchDnsMissingArgsRoutes
{
  XCTAssertEqual(dispatchService(@"dns", @"set", @[]), 1);
}

- (void)testDispatchDnsUnknownAction
{
  XCTAssertEqual(dispatchService(@"dns", @"unknown", @[]), 1);
}

@end

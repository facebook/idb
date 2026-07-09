/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/ContactsService.h>

@interface SimulatorFrameworkBridgeSmokeTests : XCTestCase
@end

@implementation SimulatorFrameworkBridgeSmokeTests

- (void)testContactsUnknownActionReturnsFailure
{
  XCTAssertEqual(handleContactsAction(@"nonexistent"), 1);
}

@end

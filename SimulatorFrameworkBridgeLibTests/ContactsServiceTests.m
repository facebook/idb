/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/ContactsService.h>

@interface ContactsServiceTests : XCTestCase
@end

@implementation ContactsServiceTests

- (void)testUnknownActionReturnsFailure
{
  XCTAssertEqual(handleContactsAction(@"delete"), 1);
  XCTAssertEqual(handleContactsAction(@""), 1);
  XCTAssertEqual(handleContactsAction(@"add"), 1);
}

@end

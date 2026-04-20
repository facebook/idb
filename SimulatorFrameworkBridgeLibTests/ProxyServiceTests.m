/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/ProxyService.h>

@interface ProxyServiceTests : XCTestCase
@end

@implementation ProxyServiceTests

- (void)testUnknownActionReturnsFailure
{
  XCTAssertEqual(handleProxyAction(@"unknown", @[]), 1);
  XCTAssertEqual(handleProxyAction(@"", @[]), 1);
  XCTAssertEqual(handleProxyAction(@"remove", @[]), 1);
}

- (void)testSetWithNoArgsReturnsFailure
{
  XCTAssertEqual(handleProxyAction(@"set", @[]), 1);
}

- (void)testSetWithOneArgReturnsFailure
{
  XCTAssertEqual(handleProxyAction(@"set", @[@"127.0.0.1"]), 1);
}

@end

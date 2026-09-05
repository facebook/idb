/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/DnsService.h>

@interface DnsServiceTests : XCTestCase
@end

@implementation DnsServiceTests

#pragma mark - buildDnsDict

- (void)testBuildDnsDictMultipleServers
{
  NSDictionary<NSString *, id> *dict = buildDnsDict(@[@"8.8.8.8", @"8.8.4.4", @"1.1.1.1"]);

  NSArray *servers = dict[@"ServerAddresses"];
  XCTAssertEqual(servers.count, 3u);
  XCTAssertEqualObjects(servers[0], @"8.8.8.8");
  XCTAssertEqualObjects(servers[1], @"8.8.4.4");
  XCTAssertEqualObjects(servers[2], @"1.1.1.1");
}

#pragma mark - handleDnsAction

// `SCDynamicStoreCreate` returns NULL for a sandboxed app, and an XCTest bundle runs inside
// one, so no action that needs a store can get past that point here. In production the bridge
// is `simctl spawn`'d rather than launched as an app and does get a store, which is why these
// tests can only pin the store-unavailable path. Everything above this point is pure and is
// covered for real.
- (void)testHandleDnsActionListReturnsFailureWithoutADynamicStore
{
  int result = handleDnsAction(@"list", @[]);
  XCTAssertEqual(result, 1);
}

- (void)testHandleDnsActionSetMissingArgsReturnsFailure
{
  XCTAssertEqual(handleDnsAction(@"set", @[]), 1);
}

- (void)testHandleDnsActionUnknownActionReturnsFailure
{
  XCTAssertEqual(handleDnsAction(@"unknown", @[]), 1);
}

@end

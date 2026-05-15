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

- (void)testBuildDnsDictContainsServerAddresses
{
  NSDictionary<NSString *, id> *dict = buildDnsDict(@[@"8.8.8.8"]);
  XCTAssertNotNil(dict);

  NSArray *servers = dict[@"ServerAddresses"];
  XCTAssertEqual(servers.count, 1u);
  XCTAssertEqualObjects(servers[0], @"8.8.8.8");
}

- (void)testBuildDnsDictMultipleServers
{
  NSDictionary<NSString *, id> *dict = buildDnsDict(@[@"8.8.8.8", @"8.8.4.4", @"1.1.1.1"]);

  NSArray *servers = dict[@"ServerAddresses"];
  XCTAssertEqual(servers.count, 3u);
  XCTAssertEqualObjects(servers[0], @"8.8.8.8");
  XCTAssertEqualObjects(servers[1], @"8.8.4.4");
  XCTAssertEqualObjects(servers[2], @"1.1.1.1");
}

#pragma mark - buildEmptyDnsDict

- (void)testBuildEmptyDnsDictIsEmpty
{
  NSDictionary<NSString *, id> *dict = buildEmptyDnsDict();
  XCTAssertNotNil(dict);
  XCTAssertEqual(dict.count, 0u);
}

#pragma mark - handleDnsAction

- (void)testHandleDnsActionListCompletes
{
  int result = handleDnsAction(@"list", @[]);
  XCTAssertEqual(result, 0);
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

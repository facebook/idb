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

#pragma mark - buildHTTPProxyDict

- (void)testBuildHTTPProxyDictContainsHTTPKeys
{
  NSDictionary<NSString *, id> *dict = buildHTTPProxyDict(@"10.0.0.1", 8080);
  XCTAssertNotNil(dict);

  XCTAssertEqualObjects(dict[@"HTTPProxy"], @"10.0.0.1");
  XCTAssertEqualObjects(dict[@"HTTPPort"], @8080);
  XCTAssertEqualObjects(dict[@"HTTPEnable"], @1);
}

- (void)testBuildHTTPProxyDictContainsHTTPSKeys
{
  NSDictionary<NSString *, id> *dict = buildHTTPProxyDict(@"proxy.example.com", 3128);

  XCTAssertEqualObjects(dict[@"HTTPSProxy"], @"proxy.example.com");
  XCTAssertEqualObjects(dict[@"HTTPSPort"], @3128);
  XCTAssertEqualObjects(dict[@"HTTPSEnable"], @1);
}

- (void)testBuildHTTPProxyDictContainsFTPPassiveAndExceptions
{
  NSDictionary<NSString *, id> *dict = buildHTTPProxyDict(@"127.0.0.1", 8080);

  XCTAssertEqualObjects(dict[@"FTPPassive"], @1);
  NSArray *exceptions = dict[@"ExceptionsList"];
  XCTAssertEqual(exceptions.count, 2u);
  XCTAssertTrue([exceptions containsObject:@"*.local"]);
  XCTAssertTrue([exceptions containsObject:@"169.254/16"]);
}

#pragma mark - buildSOCKSProxyDict

- (void)testBuildSOCKSProxyDictContainsSOCKSKeys
{
  NSDictionary<NSString *, id> *dict = buildSOCKSProxyDict(@"10.0.0.1", 1080);
  XCTAssertNotNil(dict);

  XCTAssertEqualObjects(dict[@"SOCKSProxy"], @"10.0.0.1");
  XCTAssertEqualObjects(dict[@"SOCKSPort"], @1080);
  XCTAssertEqualObjects(dict[@"SOCKSEnable"], @1);
}

- (void)testBuildSOCKSProxyDictDoesNotContainHTTPKeys
{
  NSDictionary<NSString *, id> *dict = buildSOCKSProxyDict(@"10.0.0.1", 1080);

  XCTAssertNil(dict[@"HTTPProxy"]);
  XCTAssertNil(dict[@"HTTPPort"]);
  XCTAssertNil(dict[@"HTTPEnable"]);
  XCTAssertNil(dict[@"HTTPSProxy"]);
  XCTAssertNil(dict[@"HTTPSPort"]);
  XCTAssertNil(dict[@"HTTPSEnable"]);
}

- (void)testBuildSOCKSProxyDictContainsFTPPassiveAndExceptions
{
  NSDictionary<NSString *, id> *dict = buildSOCKSProxyDict(@"10.0.0.1", 1080);

  XCTAssertEqualObjects(dict[@"FTPPassive"], @1);
  NSArray *exceptions = dict[@"ExceptionsList"];
  XCTAssertEqual(exceptions.count, 2u);
  XCTAssertTrue([exceptions containsObject:@"*.local"]);
  XCTAssertTrue([exceptions containsObject:@"169.254/16"]);
}

#pragma mark - buildEmptyProxyDict

- (void)testBuildEmptyProxyDictContainsOnlyFTPPassive
{
  NSDictionary<NSString *, id> *dict = buildEmptyProxyDict();
  XCTAssertNotNil(dict);

  XCTAssertEqual(dict.count, 1u);
  XCTAssertEqualObjects(dict[@"FTPPassive"], @1);
}

#pragma mark - handleProxyAction list

- (void)testHandleProxyActionListCompletes
{
  int result = handleProxyAction(@"list", @[]);
  XCTAssertEqual(result, 0);
}

@end

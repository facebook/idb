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
  CFMutableDictionaryRef dict = buildHTTPProxyDict(@"10.0.0.1", 8080);
  XCTAssertNotEqual(dict, NULL);

  NSDictionary *ns = (__bridge NSDictionary *)dict;
  XCTAssertEqualObjects(ns[@"HTTPProxy"], @"10.0.0.1");
  XCTAssertEqualObjects(ns[@"HTTPPort"], @8080);
  XCTAssertEqualObjects(ns[@"HTTPEnable"], @1);

  CFRelease(dict);
}

- (void)testBuildHTTPProxyDictContainsHTTPSKeys
{
  CFMutableDictionaryRef dict = buildHTTPProxyDict(@"proxy.example.com", 3128);
  NSDictionary *ns = (__bridge NSDictionary *)dict;

  XCTAssertEqualObjects(ns[@"HTTPSProxy"], @"proxy.example.com");
  XCTAssertEqualObjects(ns[@"HTTPSPort"], @3128);
  XCTAssertEqualObjects(ns[@"HTTPSEnable"], @1);

  CFRelease(dict);
}

- (void)testBuildHTTPProxyDictContainsFTPPassiveAndExceptions
{
  CFMutableDictionaryRef dict = buildHTTPProxyDict(@"127.0.0.1", 8080);
  NSDictionary *ns = (__bridge NSDictionary *)dict;

  XCTAssertEqualObjects(ns[@"FTPPassive"], @1);
  NSArray *exceptions = ns[@"ExceptionsList"];
  XCTAssertEqual(exceptions.count, 2u);
  XCTAssertTrue([exceptions containsObject:@"*.local"]);
  XCTAssertTrue([exceptions containsObject:@"169.254/16"]);

  CFRelease(dict);
}

#pragma mark - buildSOCKSProxyDict

- (void)testBuildSOCKSProxyDictContainsSOCKSKeys
{
  CFMutableDictionaryRef dict = buildSOCKSProxyDict(@"10.0.0.1", 1080);
  XCTAssertNotEqual(dict, NULL);

  NSDictionary *ns = (__bridge NSDictionary *)dict;
  XCTAssertEqualObjects(ns[@"SOCKSProxy"], @"10.0.0.1");
  XCTAssertEqualObjects(ns[@"SOCKSPort"], @1080);
  XCTAssertEqualObjects(ns[@"SOCKSEnable"], @1);

  CFRelease(dict);
}

- (void)testBuildSOCKSProxyDictDoesNotContainHTTPKeys
{
  CFMutableDictionaryRef dict = buildSOCKSProxyDict(@"10.0.0.1", 1080);
  NSDictionary *ns = (__bridge NSDictionary *)dict;

  XCTAssertNil(ns[@"HTTPProxy"]);
  XCTAssertNil(ns[@"HTTPPort"]);
  XCTAssertNil(ns[@"HTTPEnable"]);
  XCTAssertNil(ns[@"HTTPSProxy"]);
  XCTAssertNil(ns[@"HTTPSPort"]);
  XCTAssertNil(ns[@"HTTPSEnable"]);

  CFRelease(dict);
}

- (void)testBuildSOCKSProxyDictContainsFTPPassiveAndExceptions
{
  CFMutableDictionaryRef dict = buildSOCKSProxyDict(@"10.0.0.1", 1080);
  NSDictionary *ns = (__bridge NSDictionary *)dict;

  XCTAssertEqualObjects(ns[@"FTPPassive"], @1);
  NSArray *exceptions = ns[@"ExceptionsList"];
  XCTAssertEqual(exceptions.count, 2u);
  XCTAssertTrue([exceptions containsObject:@"*.local"]);
  XCTAssertTrue([exceptions containsObject:@"169.254/16"]);

  CFRelease(dict);
}

#pragma mark - buildEmptyProxyDict

- (void)testBuildEmptyProxyDictContainsOnlyFTPPassive
{
  CFMutableDictionaryRef dict = buildEmptyProxyDict();
  XCTAssertNotEqual(dict, NULL);

  NSDictionary *ns = (__bridge NSDictionary *)dict;
  XCTAssertEqual(ns.count, 1u);
  XCTAssertEqualObjects(ns[@"FTPPassive"], @1);

  CFRelease(dict);
}

@end

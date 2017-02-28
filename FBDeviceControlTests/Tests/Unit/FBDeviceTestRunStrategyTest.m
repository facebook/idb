/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>
#import <FBDeviceControl/FBDeviceControl.h>

@interface FBDeviceXCTestCommandsTest : XCTestCase

@end

@implementation FBDeviceXCTestCommandsTest

- (void)testBuildXCTestRunProperties {

  NSString *testHostPath = @"/tmp/test_host_path.app";
  NSString *testBundlePath = @"/tmp/test_host_path.app/test_bundle_path.xctest";

  FBDevice *device = [[FBDevice alloc] init];
  FBDeviceXCTestCommands *strategy = [FBDeviceXCTestCommands
    strategyWithDevice:device
    testHostPath:testHostPath
    testBundlePath:testBundlePath
    withTimeout:0
    withArguments: @[]];

  NSDictionary *properties = [strategy buildXCTestRunProperties];
  NSDictionary *stubBundleProperties = properties[@"StubBundleId"];

  XCTAssertNotNil(stubBundleProperties);

  XCTAssertEqualObjects(stubBundleProperties[@"TestHostPath"], testHostPath);
  XCTAssertEqualObjects(stubBundleProperties[@"TestBundlePath"], testBundlePath);
  XCTAssertEqualObjects(stubBundleProperties[@"UseUITargetAppProvidedByTests"], @YES);
  XCTAssertEqualObjects(stubBundleProperties[@"IsUITestBundle"], @YES);
}

@end

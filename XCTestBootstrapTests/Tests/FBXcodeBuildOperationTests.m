/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

@interface FBXcodeBuildOperationTests : XCTestCase

@end

@implementation FBXcodeBuildOperationTests

- (void)testUITestConfiguration
{
  NSString *testHostPath = @"/tmp/test_host_path.app";
  NSString *testBundlePath = @"/tmp/test_host_path.app/test_bundle_path.xctest";

  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithBundleID:@"com.bundle.id"
    bundleName:@"BundleName"
    arguments:@[]
    environment:@{}
    waitForDebugger:NO
    output:FBProcessOutputConfiguration.outputToDevNull];

  FBTestLaunchConfiguration *configuration = [[[FBTestLaunchConfiguration
    configurationWithTestBundlePath:testBundlePath]
    withTestHostPath:testHostPath]
    withApplicationLaunchConfiguration:appLaunch];

  NSDictionary *properties = [FBXcodeBuildOperation xctestRunProperties:configuration];
  NSDictionary *stubBundleProperties = properties[@"StubBundleId"];

  XCTAssertNotNil(stubBundleProperties);

  XCTAssertEqualObjects(stubBundleProperties[@"TestHostPath"], testHostPath);
  XCTAssertEqualObjects(stubBundleProperties[@"TestBundlePath"], testBundlePath);
  XCTAssertEqualObjects(stubBundleProperties[@"UseUITargetAppProvidedByTests"], @YES);
  XCTAssertEqualObjects(stubBundleProperties[@"IsUITestBundle"], @YES);
}

@end

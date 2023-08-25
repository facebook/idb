/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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
  FBBundleDescriptor *testHostBundle = [[FBBundleDescriptor alloc] initWithName:@"test.host.app" identifier:@"test.host.app" path:testHostPath binary:nil];

  NSString *testBundlePath = @"/tmp/test_host_path.app/test_bundle_path.xctest";
  FBBundleDescriptor *testBundle = [[FBBundleDescriptor alloc] initWithName:@"test.bundle" identifier:@"test.bundle" path:testBundlePath binary:nil];

  FBApplicationLaunchConfiguration *appLaunch = [[FBApplicationLaunchConfiguration alloc]
    initWithBundleID:@"com.bundle.id"
    bundleName:@"BundleName"
    arguments:@[]
    environment:@{}
    waitForDebugger:NO
    io:FBProcessIO.outputToDevNull
    launchMode:FBApplicationLaunchModeFailIfRunning];

  FBTestLaunchConfiguration *configuration = [[FBTestLaunchConfiguration alloc]
    initWithTestBundle:testBundle
    applicationLaunchConfiguration:appLaunch
    testHostBundle:testHostBundle
    timeout:0
    initializeUITesting:NO
    useXcodebuild:NO
    testsToRun:nil
    testsToSkip:nil
    targetApplicationBundle:nil
    xcTestRunProperties:nil
    resultBundlePath:nil
    reportActivities:NO
    coverageDirectoryPath:nil
    enableContinuousCoverageCollection:NO
    logDirectoryPath:nil
    reportResultBundle:NO];

  NSDictionary *properties = [FBXcodeBuildOperation xctestRunProperties:configuration];
  NSDictionary *stubBundleProperties = properties[@"StubBundleId"];

  XCTAssertNotNil(stubBundleProperties);

  XCTAssertEqualObjects(stubBundleProperties[@"TestHostPath"], testHostPath);
  XCTAssertEqualObjects(stubBundleProperties[@"TestBundlePath"], testBundlePath);
  XCTAssertEqualObjects(stubBundleProperties[@"UseUITargetAppProvidedByTests"], @YES);
  XCTAssertEqualObjects(stubBundleProperties[@"IsUITestBundle"], @YES);
}

@end

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

@interface FBTestRunnerConfigurationTests : XCTestCase

@end

@implementation FBTestRunnerConfigurationTests

- (void)testLaunchEnvironment
{
  FBBinaryDescriptor *testBundleBinary = [[FBBinaryDescriptor alloc] initWithName:@"TestBinaryName" architectures:NSSet.set uuid:NSUUID.UUID path:@"/blackhole/xctwda.xctest/test"];
  FBBundleDescriptor *testBundle = [[FBBundleDescriptor alloc] initWithName:@"TestBundleName" identifier:@"TestBundleIdentifier" path:@"/blackhole/xctwda.xctest" binary:testBundleBinary];

  FBBinaryDescriptor *hostApplicationBinary = [[FBBinaryDescriptor alloc] initWithName:@"HostApplicationBinaryName" architectures:NSSet.set uuid:NSUUID.UUID path:@"/blackhole/pray.app/app"];
  FBBundleDescriptor *hostApplication = [[FBBundleDescriptor alloc] initWithName:@"HostApplicationName" identifier:@"HostApplicationIdentifier" path:@"/blackhole/pray.app" binary:hostApplicationBinary];

  NSDictionary<NSString *, NSString *> *expected = @{
    @"AppTargetLocation" : @"/blackhole/pray.app/app",
    @"DYLD_FALLBACK_FRAMEWORK_PATH" : @"/Apple",
    @"DYLD_FALLBACK_LIBRARY_PATH" : @"/Apple",
    @"OBJC_DISABLE_GC" : @"YES",
    @"MAGIC": @"IS_HERE",
    @"TestBundleLocation" : @"/blackhole/xctwda.xctest",
    @"XCODE_DBG_XPC_EXCLUSIONS" : @"com.apple.dt.xctestSymbolicator",
    @"XCTestConfigurationFilePath" : @"/booo/magic.xctestconfiguration",
  };
  NSDictionary<NSString *, NSString *> *actual = [FBTestRunnerConfiguration
    launchEnvironmentWithHostApplication:hostApplication
    hostApplicationAdditionalEnvironment:@{@"MAGIC": @"IS_HERE"}
    testBundle:testBundle
    testConfigurationPath:@"/booo/magic.xctestconfiguration"
    frameworkSearchPaths:@[@"/Apple"]];
  XCTAssertEqualObjects(expected, actual);
}

@end

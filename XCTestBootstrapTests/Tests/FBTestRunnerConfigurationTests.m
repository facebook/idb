/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <OCMock/OCMock.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

@interface FBTestRunnerConfigurationTests : XCTestCase

@end

@implementation FBTestRunnerConfigurationTests

- (FBTestRunnerConfiguration *)buildConfiguration
{
  id testBundleMock = [OCMockObject mockForClass:FBTestBundle.class];
  [[[testBundleMock stub] andReturn:@"/blackhole/xctwda.xctest"] path];

  id appBundleMock = [OCMockObject mockForClass:FBProductBundle.class];
  [[[appBundleMock stub] andReturn:@"/blackhole/pray.app"] path];
  [[[appBundleMock stub] andReturn:@"/blackhole/pray.app/app"] binaryPath];

  return [FBTestRunnerConfiguration
    configurationWithSessionIdentifier:NSUUID.UUID
    hostApplication:appBundleMock
    hostApplicationAdditionalEnvironment:@{@"MAGIC": @"IS_HERE"}
    testBundle:testBundleMock
    testConfigurationPath:@"/booo/magic.xctestconfiguration"
    frameworkSearchPath:@"/Apple"
    testedApplicationAdditionalEnvironment:nil];
}

- (void)testLaunchArguments
{
  NSArray<NSString *> *expected = @[@"-NSTreatUnknownArgumentsAsOpen", @"NO", @"-ApplePersistenceIgnoreState", @"YES"];
  XCTAssertEqualObjects(self.buildConfiguration.launchArguments, expected);
  XCTAssertEqualObjects([[self.buildConfiguration copy] launchArguments], expected);
}

- (void)testLaunchEnvironment
{
  NSDictionary<NSString *, NSString *> *expected = @{
    @"AppTargetLocation" : @"/blackhole/pray.app/app",
    @"DYLD_FRAMEWORK_PATH" : @"/blackhole/pray.app/Frameworks",
    @"DYLD_LIBRARY_PATH" : @"/blackhole/pray.app/Frameworks",
    @"DYLD_FALLBACK_FRAMEWORK_PATH" : @"/Apple",
    @"DYLD_FALLBACK_LIBRARY_PATH" : @"/Apple",
    @"OBJC_DISABLE_GC" : @"YES",
    @"MAGIC": @"IS_HERE",
    @"TestBundleLocation" : @"/blackhole/xctwda.xctest",
    @"XCODE_DBG_XPC_EXCLUSIONS" : @"com.apple.dt.xctestSymbolicator",
    @"XCTestConfigurationFilePath" : @"/booo/magic.xctestconfiguration",
  };
  XCTAssertEqualObjects(self.buildConfiguration.launchEnvironment, expected);
  XCTAssertEqualObjects([[self.buildConfiguration copy] launchEnvironment], expected);
}

@end

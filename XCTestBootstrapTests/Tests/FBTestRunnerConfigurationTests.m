/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
  [[[appBundleMock stub] andReturn:@"/blackhole/pray.app/app"] binaryPath];

  id IDEBundleInjectionMock = [OCMockObject mockForClass:FBProductBundle.class];
  [[[IDEBundleInjectionMock stub] andReturn:@"/whitehole/IDEBI.framework/rrr"] binaryPath];

  return [FBTestRunnerConfiguration
    configurationWithSessionIdentifier:NSUUID.UUID
    hostApplication:appBundleMock
    ideInjectionFramework:IDEBundleInjectionMock
    testBundle:testBundleMock
    testConfigurationPath:@"/booo/magic.xctestconfiguration"
    frameworkSearchPath:@"/Apple"];
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
    @"DYLD_INSERT_LIBRARIES" : @"/whitehole/IDEBI.framework/rrr",
    @"DYLD_FRAMEWORK_PATH" : @"/Apple",
    @"DYLD_LIBRARY_PATH" : @"/Apple",
    @"OBJC_DISABLE_GC" : @"YES",
    @"TestBundleLocation" : @"/blackhole/xctwda.xctest",
    @"XCInjectBundle" : @"/blackhole/xctwda.xctest",
    @"XCInjectBundleInto" : @"/blackhole/pray.app/app",
    @"XCODE_DBG_XPC_EXCLUSIONS" : @"com.apple.dt.xctestSymbolicator",
    @"XCTestConfigurationFilePath" : @"/booo/magic.xctestconfiguration",
  };
  XCTAssertEqualObjects(self.buildConfiguration.launchEnvironment, expected);
  XCTAssertEqualObjects([[self.buildConfiguration copy] launchEnvironment], expected);
}

@end

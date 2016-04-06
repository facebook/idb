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

#import "FBApplicationDataPackage.h"
#import "FBCodesignProvider.h"
#import "FBFileManager.h"
#import "FBTestBundle.h"
#import "FBTestConfiguration.h"

@class FBTestBundle;

@interface FBApplicationDataPackageTests : XCTestCase
@end

@implementation FBApplicationDataPackageTests

+ (NSUUID *)sessionIdentifier
{
  return [[NSUUID alloc] initWithUUIDString:@"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"];
}

- (FBApplicationDataPackage *)buildSilentPackageWithCodeSigner:(id<FBCodesignProvider>)codesigner
{
  OCMockObject<FBFileManager> *fileManagerMock = [OCMockObject niceMockForProtocol:@protocol(FBFileManager)];
  [[[[fileManagerMock stub] andReturnValue:@YES] ignoringNonObjectArgs] createDirectoryAtPath:[OCMArg any] withIntermediateDirectories:YES attributes:[OCMArg any] error:[OCMArg anyObjectRef]];
  [[[fileManagerMock stub] andReturnValue:@YES] copyItemAtPath:[OCMArg any] toPath:[OCMArg any] error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock stub] andReturnValue:@YES] ignoringNonObjectArgs] writeData:[OCMArg any] toFile:[OCMArg any] options:YES error:[OCMArg anyObjectRef]];

  id testConfigurationMock = [OCMockObject mockForClass:FBTestConfiguration.class];
  [[[testConfigurationMock stub] andReturn:[self.class sessionIdentifier]] sessionIdentifier];

  id testBundleMock = [OCMockObject mockForClass:FBTestBundle.class];
  [[[testBundleMock stub] andReturn:@"/test/Magic.xctest"] path];
  [[[testBundleMock stub] andReturn:@"Magic"] name];
  [[[testBundleMock stub] andReturn:@"Magic.xctest"] filename];
  [[[testBundleMock stub] andReturn:testConfigurationMock] configuration];

  return
  [[[[[[[FBApplicationDataPackageBuilder builderWithFileManager:fileManagerMock]
        withTestBundle:testBundleMock]
       withWorkingDirectory:@"/Middle/of/nowhere"]
      withDeviceDataDirectory:@"/device/somewhere"]
     withPlatformDirectory:@"/platform/ibuddy"]
    withCodesignProvider:codesigner]
   build];
}

- (void)testDataPackageCreation
{
  OCMockObject<FBFileManager> *fileManagerMock = [OCMockObject mockForProtocol:@protocol(FBFileManager)];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] createDirectoryAtPath:@"/Middle/of/nowhere/Magic.xcappdata/AppData/tmp/TestPlans" withIntermediateDirectories:YES attributes:[OCMArg any] error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] copyItemAtPath:@"/platform/ibuddy/Developer/Library/Frameworks/XCTest.framework" toPath:@"/Middle/of/nowhere/Magic.xcappdata/AppData/tmp/XCTest.framework" error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] copyItemAtPath:@"/platform/ibuddy/Developer/Library/PrivateFrameworks/IDEBundleInjection.framework" toPath:@"/Middle/of/nowhere/Magic.xcappdata/AppData/tmp/IDEBundleInjection.framework" error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] copyItemAtPath:@"/test/Magic.xctest" toPath:@"/Middle/of/nowhere/Magic.xcappdata/AppData/tmp/Magic.xctest" error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] writeData:[OCMArg any] toFile:@"/Middle/of/nowhere/Magic.xcappdata/AppData/tmp/TestPlans/Magic.xctest.xctestconfiguration" options:YES error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] writeData:[OCMArg any] toFile:@"/Middle/of/nowhere/Magic.xcappdata/AppData/tmp/Magic.xctest/Magic-E621E1F8-C36C-495A-93FC-0C247A3E6E5F.xctestconfiguration" options:YES error:[OCMArg anyObjectRef]];

  [[[[fileManagerMock stub] andReturnValue:@YES] ignoringNonObjectArgs] createDirectoryAtPath:@"/Middle/of/nowhere/Magic.xcappdata/AppData/tmp" withIntermediateDirectories:YES attributes:[OCMArg any] error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock stub] andReturnValue:@NO] ignoringNonObjectArgs] fileExistsAtPath:[OCMArg any]];
  [[[fileManagerMock stub] andReturn:nil] dictionaryWithPath:[OCMArg any]];

  id testConfigurationMock = [OCMockObject mockForClass:FBTestConfiguration.class];
  [[[testConfigurationMock stub] andReturn:[self.class sessionIdentifier]] sessionIdentifier];

  id testBundleMock = [OCMockObject mockForClass:FBTestBundle.class];
  [[[testBundleMock stub] andReturn:@"/test/Magic.xctest"] path];
  [[[testBundleMock stub] andReturn:@"Magic"] name];
  [[[testBundleMock stub] andReturn:@"Magic.xctest"] filename];
  [[[testBundleMock stub] andReturn:testConfigurationMock] configuration];

  FBApplicationDataPackage *package =
  [[[[[[FBApplicationDataPackageBuilder builderWithFileManager:fileManagerMock]
       withTestBundle:testBundleMock]
      withWorkingDirectory:@"/Middle/of/nowhere"]
     withDeviceDataDirectory:@"/device/somewhere"]
    withPlatformDirectory:@"/platform/ibuddy"]
   build];

  XCTAssertNotNil(package.testConfiguration);
  XCTAssertNotNil(package.testBundle);
  XCTAssertNotNil(package.XCTestFramework);
  XCTAssertNotNil(package.IDEBundleInjectionFramework);

  [fileManagerMock verify];
}

- (void)testTestConfiguration
{
  FBTestConfiguration *testConfiguration = [self buildSilentPackageWithCodeSigner:nil].testConfiguration;
  XCTAssertNotNil(testConfiguration);
  XCTAssertTrue([testConfiguration isKindOfClass:FBTestConfiguration.class]);
  XCTAssertEqualObjects(testConfiguration.moduleName, @"Magic");
  XCTAssertEqualObjects(testConfiguration.sessionIdentifier, [self.class sessionIdentifier]);
  XCTAssertEqualObjects(testConfiguration.testBundlePath, @"/device/somewhere/tmp/Magic.xctest");
  XCTAssertEqualObjects(testConfiguration.path, @"/Middle/of/nowhere/Magic.xcappdata/AppData/tmp/TestPlans/Magic.xctest.xctestconfiguration");
}

- (void)testTestBundle
{
  FBTestBundle *testBundle = [self buildSilentPackageWithCodeSigner:nil].testBundle;
  XCTAssertNotNil(testBundle);
  XCTAssertTrue([testBundle isKindOfClass:FBTestBundle.class]);
  XCTAssertEqualObjects(testBundle.path, @"/Middle/of/nowhere/Magic.xcappdata/AppData/tmp/Magic.xctest");
}

- (void)testXCTestFramework
{
  FBProductBundle *product = [self buildSilentPackageWithCodeSigner:nil].XCTestFramework;
  XCTAssertNotNil(product);
  XCTAssertTrue([product isKindOfClass:FBProductBundle.class]);
  XCTAssertEqualObjects(product.filename, @"XCTest.framework");
  XCTAssertEqualObjects(product.path, @"/Middle/of/nowhere/Magic.xcappdata/AppData/tmp/XCTest.framework");
}

- (void)testIDEBundleInjectionFramework
{
  FBProductBundle *product = [self buildSilentPackageWithCodeSigner:nil].IDEBundleInjectionFramework;
  XCTAssertNotNil(product);
  XCTAssertEqualObjects(product.filename, @"IDEBundleInjection.framework");
  XCTAssertEqualObjects(product.path, @"/Middle/of/nowhere/Magic.xcappdata/AppData/tmp/IDEBundleInjection.framework");
}

- (void)testCodesigning
{
  OCMockObject<FBCodesignProvider> *codesignerMock = [OCMockObject mockForProtocol:@protocol(FBCodesignProvider)];
  [[codesignerMock expect] signBundleAtPath:@"/Middle/of/nowhere/Magic.xcappdata/AppData/tmp/Magic.xctest"];
  [[codesignerMock expect] signBundleAtPath:@"/Middle/of/nowhere/Magic.xcappdata/AppData/tmp/XCTest.framework"];
  [[codesignerMock expect] signBundleAtPath:@"/Middle/of/nowhere/Magic.xcappdata/AppData/tmp/IDEBundleInjection.framework"];
  [self buildSilentPackageWithCodeSigner:codesignerMock];
  [codesignerMock verify];
}

@end

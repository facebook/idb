/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import <OCMock/OCMock.h>

#import "FBTestBundle.h"
#import "FBTestConfiguration.h"
#import "FBXCTestBootstrapFixtures.h"
#import "NSFileManager+FBFileManager.h"

@interface FBTestBundleTests : XCTestCase
@end

@implementation FBTestBundleTests

- (void)testTestBundleLoadWithPath
{
  NSString *expectedTestConfigPath = @"/Deep/Deep/Darkness/SimpleTestTarget.xctest/SimpleTestTarget-E621E1F8-C36C-495A-93FC-0C247A3E6E5F.xctestconfiguration";
  NSUUID *sessionIdentifier = [[NSUUID alloc] initWithUUIDString:@"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"];
  NSBundle *bundle = [FBTestBundleTests testBundleFixture];

  OCMockObject<FBFileManager> *fileManagerMock = [OCMockObject mockForProtocol:@protocol(FBFileManager)];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] copyItemAtPath:bundle.bundlePath toPath:expectedTestConfigPath.stringByDeletingLastPathComponent error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] writeData:[OCMArg any] toFile:expectedTestConfigPath options:0 error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock stub] andReturnValue:@YES] ignoringNonObjectArgs] createDirectoryAtPath:@"/Deep/Deep/Darkness" withIntermediateDirectories:YES attributes:[OCMArg any] error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock stub] andReturnValue:@NO] ignoringNonObjectArgs] fileExistsAtPath:[OCMArg any]];
  [[[fileManagerMock stub] andReturn:nil] dictionaryWithPath:[OCMArg any]];

  FBTestBundle *testBundle =
  [[[[[FBTestBundleBuilder builderWithFileManager:fileManagerMock]
      withBundlePath:bundle.bundlePath]
     withWorkingDirectory:@"/Deep/Deep/Darkness"]
    withSessionIdentifier:sessionIdentifier]
   build];

  XCTAssertTrue([testBundle isKindOfClass:FBTestBundle.class]);
  XCTAssertNotNil(testBundle.configuration);
  XCTAssertEqualObjects(testBundle.configuration.sessionIdentifier, sessionIdentifier);
  XCTAssertEqualObjects(testBundle.configuration.moduleName, @"SimpleTestTarget");
  XCTAssertEqualObjects(testBundle.configuration.testBundlePath, expectedTestConfigPath.stringByDeletingLastPathComponent);
  XCTAssertEqualObjects(testBundle.configuration.path, expectedTestConfigPath);

  [fileManagerMock verify];
}

- (void)testNoBundlePath
{
  XCTAssertThrows([[FBTestBundleBuilder builder] build]);
}

- (void)testBundleWithoutSessionIdentifier
{
  NSBundle *bundle = [NSBundle bundleForClass:self.class];
  FBTestBundle *testBundle =
  [[[FBTestBundleBuilder builder]
    withBundlePath:bundle.bundlePath]
   build];
  XCTAssertTrue([testBundle isKindOfClass:FBTestBundle.class]);
  XCTAssertNil(testBundle.configuration);
}

@end

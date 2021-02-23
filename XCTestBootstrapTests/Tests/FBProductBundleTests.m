/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <OCMock/OCMock.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBXCTestBootstrapFixtures.h"

@interface FBProductBundleTests : XCTestCase
@end

@implementation FBProductBundleTests

- (void)testWorkingDirectory
{
  NSBundle *bundle = [FBProductBundleTests iosUnitTestBundleFixture];
  NSDictionary *plist =
  @{
    @"CFBundleIdentifier" : @"bundleID",
    @"CFBundleExecutable" : @"exec",
  };
  NSString *targetPath = @"/Heaven/iOSUnitTestFixture.xctest";
  OCMockObject<FBFileManager> *fileManagerMock = [OCMockObject mockForProtocol:@protocol(FBFileManager)];
  [[[fileManagerMock expect] andReturnValue:@YES] copyItemAtPath:bundle.bundlePath toPath:targetPath error:[OCMArg anyObjectRef]];
  [[[fileManagerMock expect] andReturn:plist] dictionaryWithPath:[bundle.bundlePath stringByAppendingPathComponent:@"Info.plist"]];
  [[[[fileManagerMock stub] andReturnValue:@YES] ignoringNonObjectArgs] createDirectoryAtPath:@"/Heaven" withIntermediateDirectories:NO attributes:[OCMArg any] error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock stub] andReturnValue:@YES] ignoringNonObjectArgs] fileExistsAtPath:@"/Heaven/iOSUnitTestFixture.xctest/exec"];
  [[[[fileManagerMock stub] andReturnValue:@NO] ignoringNonObjectArgs] fileExistsAtPath:[OCMArg any]];

  NSError *error;
  FBProductBundle *productBundle =
  [[[[FBProductBundleBuilder builderWithFileManager:fileManagerMock]
     withBundlePath:bundle.bundlePath]
    withWorkingDirectory:@"/Heaven"]
   buildWithError:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(productBundle.path, targetPath);
  XCTAssertEqualObjects(productBundle.binaryName, @"exec");
  XCTAssertEqualObjects(productBundle.bundleID, @"bundleID");
  XCTAssertEqualObjects(productBundle.binaryPath, [targetPath stringByAppendingPathComponent:@"exec"]);
  [fileManagerMock verify];
}

@end

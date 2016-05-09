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

#import "FBCodesignProvider.h"
#import "FBFileManager.h"
#import "FBProductBundle.h"
#import "FBXCTestBootstrapFixtures.h"

@interface FBProductBundleTests : XCTestCase
@end

@implementation FBProductBundleTests

- (void)testProductBundleLoadWithPath
{
  NSBundle *bundle = [FBProductBundleTests testBundleFixture];
  FBProductBundle *productBundle =
  [[[FBProductBundleBuilder builder]
    withBundlePath:bundle.bundlePath]
   build];
  XCTAssertTrue([productBundle isKindOfClass:FBProductBundle.class]);
  XCTAssertEqualObjects(productBundle.name, @"SimpleTestTarget");
  XCTAssertEqualObjects(productBundle.filename, @"SimpleTestTarget.xctest");
  XCTAssertEqualObjects(productBundle.path, bundle.bundlePath);
  XCTAssertEqualObjects(productBundle.bundleID, @"FB.SimpleTestTarget");
  XCTAssertEqualObjects(productBundle.binaryName, @"SimpleTestTarget");
  XCTAssertEqualObjects(productBundle.binaryPath, [bundle.bundlePath stringByAppendingPathComponent:@"SimpleTestTarget"]);
}

- (void)testNoBundlePath
{
  XCTAssertThrows([[FBProductBundleBuilder builder] build]);
}

- (void)testWorkingDirectory
{
  NSBundle *bundle = [FBProductBundleTests testBundleFixture];
  NSDictionary *plist =
  @{
    @"CFBundleIdentifier" : @"bundleID",
    @"CFBundleExecutable" : @"exec",
  };
  NSString *targetPath = @"/Heaven/SimpleTestTarget.xctest";
  OCMockObject<FBFileManager> *fileManagerMock = [OCMockObject mockForProtocol:@protocol(FBFileManager)];
  [[[fileManagerMock expect] andReturnValue:@YES] copyItemAtPath:bundle.bundlePath toPath:targetPath error:[OCMArg anyObjectRef]];
  [[[fileManagerMock expect] andReturn:plist] dictionaryWithPath:[bundle.bundlePath stringByAppendingPathComponent:@"Info.plist"]];
  [[[[fileManagerMock stub] andReturnValue:@YES] ignoringNonObjectArgs] createDirectoryAtPath:@"/Heaven" withIntermediateDirectories:NO attributes:[OCMArg any] error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock stub] andReturnValue:@NO] ignoringNonObjectArgs] fileExistsAtPath:[OCMArg any]];

  FBProductBundle *productBundle =
  [[[[FBProductBundleBuilder builderWithFileManager:fileManagerMock]
     withBundlePath:bundle.bundlePath]
    withWorkingDirectory:@"/Heaven"]
   build];
  XCTAssertEqualObjects(productBundle.path, targetPath);
  XCTAssertEqualObjects(productBundle.binaryName, @"exec");
  XCTAssertEqualObjects(productBundle.bundleID, @"bundleID");
  XCTAssertEqualObjects(productBundle.binaryPath, [targetPath stringByAppendingPathComponent:@"exec"]);
  [fileManagerMock verify];
}

- (void)testCodesigning
{
  NSBundle *bundle = [NSBundle bundleForClass:self.class];

  OCMockObject<FBCodesignProvider> *codesignerMock = [OCMockObject mockForProtocol:@protocol(FBCodesignProvider)];
  [[codesignerMock expect] signBundleAtPath:bundle.bundlePath];

  [[[[FBProductBundleBuilder builder]
     withBundlePath:bundle.bundlePath]
    withCodesignProvider:codesignerMock]
   build];
  [codesignerMock verify];
}

- (void)testCopyAtLocation
{
  NSBundle *bundle = [NSBundle bundleForClass:self.class];
  FBProductBundle *productBundle =
  [[[FBProductBundleBuilder builder]
    withBundlePath:bundle.bundlePath]
   build];
  FBProductBundle *productBundleCopy = [productBundle copyLocatedInDirectory:@"/Magic"];
  XCTAssertEqualObjects(productBundleCopy.name, productBundle.name);
  XCTAssertEqualObjects(productBundleCopy.filename, productBundle.filename);
  XCTAssertEqualObjects(productBundleCopy.path, [@"/Magic" stringByAppendingPathComponent:productBundleCopy.filename]);
  XCTAssertEqualObjects(productBundleCopy.bundleID, productBundle.bundleID);
  XCTAssertEqualObjects(productBundleCopy.binaryName, productBundle.binaryName);
  XCTAssertEqualObjects(productBundleCopy.binaryPath, [productBundleCopy.path stringByAppendingPathComponent:productBundle.binaryName]);
}

@end

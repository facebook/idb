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

#import "FBXCTestBootstrapFixtures.h"

@interface FBProductBundleTests : XCTestCase
@end

@implementation FBProductBundleTests

- (void)testProductBundleLoadWithPathOnIOS
{
  NSError *error;
  NSBundle *bundle = [FBProductBundleTests iosUnitTestBundleFixture];
  FBProductBundle *productBundle =
  [[[FBProductBundleBuilder builder]
    withBundlePath:bundle.bundlePath]
   buildWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue([productBundle isKindOfClass:FBProductBundle.class]);
  XCTAssertEqualObjects(productBundle.name, @"iOSUnitTestFixture");
  XCTAssertEqualObjects(productBundle.filename, @"iOSUnitTestFixture.xctest");
  XCTAssertEqualObjects(productBundle.path, bundle.bundlePath);
  XCTAssertEqualObjects(productBundle.bundleID, @"com.facebook.iOSUnitTestFixture");
  XCTAssertEqualObjects(productBundle.binaryName, @"iOSUnitTestFixture");
  XCTAssertEqualObjects(productBundle.binaryPath, [bundle.bundlePath stringByAppendingPathComponent:@"iOSUnitTestFixture"]);
}

- (void)testProductBundleLoadWithPathOnMacOSX
{
  NSError *error;
  NSBundle *bundle = [FBProductBundleTests macUnitTestBundleFixture];
  FBProductBundle *productBundle =
  [[[FBProductBundleBuilder builder]
    withBundlePath:bundle.bundlePath]
   buildWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue([productBundle isKindOfClass:FBProductBundle.class]);
  XCTAssertEqualObjects(productBundle.name, @"MacUnitTestFixture");
  XCTAssertEqualObjects(productBundle.filename, @"MacUnitTestFixture.xctest");
  XCTAssertEqualObjects(productBundle.path, bundle.bundlePath);
  XCTAssertEqualObjects(productBundle.bundleID, @"com.facebook.MacUnitTestFixture");
  XCTAssertEqualObjects(productBundle.binaryName, @"MacUnitTestFixture");
  XCTAssertEqualObjects(productBundle.binaryPath, [bundle.bundlePath stringByAppendingPathComponent:@"Contents/MacOS/MacUnitTestFixture"]);
}

- (void)testNoBundlePath
{
  XCTAssertThrows([[FBProductBundleBuilder builder] buildWithError:nil]);
}

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

- (void)testCodesigning
{
  NSBundle *bundle = [NSBundle bundleForClass:self.class];

  OCMockObject<FBCodesignProvider> *codesignerMock = [OCMockObject mockForProtocol:@protocol(FBCodesignProvider)];
  [[[codesignerMock expect] andReturn:[FBFuture futureWithResult:NSNull.null]] signBundleAtPath:bundle.bundlePath];

  NSError *error;
  [[[[FBProductBundleBuilder builder]
     withBundlePath:bundle.bundlePath]
    withCodesignProvider:codesignerMock]
   buildWithError:&error];
  XCTAssertNil(error);
  [codesignerMock verify];
}

- (void)testCopyAtLocation
{
  NSBundle *bundle = [NSBundle bundleForClass:self.class];
  NSError *error;
  FBProductBundle *productBundle =
  [[[FBProductBundleBuilder builder]
    withBundlePath:bundle.bundlePath]
   buildWithError:&error];
  XCTAssertNil(error);
  FBProductBundle *productBundleCopy = [productBundle copyLocatedInDirectory:@"/Magic"];
  XCTAssertEqualObjects(productBundleCopy.name, productBundle.name);
  XCTAssertEqualObjects(productBundleCopy.filename, productBundle.filename);
  XCTAssertEqualObjects(productBundleCopy.path, [@"/Magic" stringByAppendingPathComponent:productBundleCopy.filename]);
  XCTAssertEqualObjects(productBundleCopy.bundleID, productBundle.bundleID);
  XCTAssertEqualObjects(productBundleCopy.binaryName, productBundle.binaryName);
  XCTAssertEqualObjects(productBundleCopy.binaryPath, [productBundleCopy.path stringByAppendingPathComponent:productBundle.binaryName]);
}

@end

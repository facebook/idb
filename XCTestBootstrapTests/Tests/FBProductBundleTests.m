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
  [[[codesignerMock expect] andReturn:FBFuture.empty] signBundleAtPath:bundle.bundlePath];

  NSError *error;
  [[[[FBProductBundleBuilder builder]
     withBundlePath:bundle.bundlePath]
    withCodesignProvider:codesignerMock]
   buildWithError:&error];
  XCTAssertNil(error);
  [codesignerMock verify];
}

- (void)testFromInstalledApplication
{
  FBInstalledApplication *application = [FBInstalledApplication
    installedApplicationWithBundle:[[FBBundleDescriptor alloc] initWithName:@"FooApp" identifier:@"com.foo.app" path:@"/Foo.app" binary:nil]
    installType:FBApplicationInstallTypeUser
    dataContainer:@"/tmp/container"];
  NSError *error = nil;
  FBProductBundle *bundle = [FBProductBundleBuilder productBundleFromInstalledApplication:application error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(bundle.binaryName, @"FooApp");
}

@end

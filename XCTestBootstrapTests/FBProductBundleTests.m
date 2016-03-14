 // Copyright 2004-present Facebook. All Rights Reserved.

#import <XCTest/XCTest.h>

#import <OCMock/OCMock.h>

#import "FBCodesignProvider.h"
#import "FBFileManager.h"
#import "FBProductBundle.h"

@interface FBProductBundleTests : XCTestCase
@end

@implementation FBProductBundleTests

- (void)testProductBundleLoadWithPath
{
  NSBundle *bundle = [NSBundle bundleForClass:self.class];
  FBProductBundle *productBundle =
  [[[FBProductBundleBuilder builder]
    withBundlePath:bundle.bundlePath]
   build];
  XCTAssertTrue([productBundle isKindOfClass:FBProductBundle.class]);
  XCTAssertEqualObjects(productBundle.name, @"XCTestBootstrapTests");
  XCTAssertEqualObjects(productBundle.filename, @"XCTestBootstrapTests.xctest");
  XCTAssertEqualObjects(productBundle.path, bundle.bundlePath);
  XCTAssertEqualObjects(productBundle.bundleID, @"facebook.XCTestBootstrapTests");
  XCTAssertEqualObjects(productBundle.binaryName, @"XCTestBootstrapTests");
  XCTAssertEqualObjects(productBundle.binaryPath, [bundle.bundlePath stringByAppendingPathComponent:@"XCTestBootstrapTests"]);
}

- (void)testNoBundlePath
{
  XCTAssertThrows([[FBProductBundleBuilder builder] build]);
}

- (void)testWorkingDirectory
{
  NSBundle *bundle = [NSBundle bundleForClass:self.class];
  NSDictionary *plist =
  @{
    @"CFBundleIdentifier" : @"bundleID",
    @"CFBundleExecutable" : @"exec",
  };
  NSString *targetPath = @"/Heaven/XCTestBootstrapTests.xctest";
  OCMockObject<FBFileManager> *fileManagerMock = [OCMockObject mockForProtocol:@protocol(FBFileManager)];
  [[[fileManagerMock expect] andReturnValue:@YES] copyItemAtPath:bundle.bundlePath toPath:targetPath error:[OCMArg anyObjectRef]];
  [[[fileManagerMock expect] andReturn:plist] dictionaryWithPath:[bundle.bundlePath stringByAppendingPathComponent:@"Info.plist"]];

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

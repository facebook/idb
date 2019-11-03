/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestKitFixtures.h"

#import <FBControlCore/FBControlCore.h>

@implementation FBXCTestKitFixtures

+ (NSString *)createTemporaryDirectory
{
  NSError *error;
  NSFileManager *fileManager = [NSFileManager defaultManager];

  NSString *temporaryDirectory =
      [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  [fileManager createDirectoryAtPath:temporaryDirectory withIntermediateDirectories:YES attributes:nil error:&error];
  NSAssert(!error, @"Could not create temporary directory");

  return temporaryDirectory;
}

+ (NSString *)tableSearchApplicationPath
{
  return [[[NSBundle bundleForClass:self] pathForResource:@"TableSearch" ofType:@"app"]
      stringByAppendingPathComponent:@"TableSearch"];
}

+ (NSString *)testRunnerApp
{
  return [[[NSBundle bundleForClass:self] pathForResource:@"FBTestRunnerApp" ofType:@"app"]
          stringByAppendingPathComponent:@"FBTestRunnerApp"];
}

+ (NSString *)iOSUnitTestBundlePath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"iOSUnitTestFixture" ofType:@"xctest"];
}

+ (NSString *)macUnitTestBundlePath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"MacUnitTestFixture" ofType:@"xctest"];
}

+ (NSString *)macUITestBundlePath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"MacAppUITestsFixture" ofType:@"xctest"];
}

+ (NSString *)macCommonAppPath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"MacCommonApp" ofType:@"app"];
}

+ (NSString *)macUITestAppTargetPath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"MacAppFixture" ofType:@"app"];
}

+ (NSString *)iOSUITestAppTargetPath
{
  return [[[NSBundle bundleForClass:self] pathForResource:@"iOSAppFixture" ofType:@"app"]
      stringByAppendingPathComponent:@"iOSAppFixture"];
}

+ (NSString *)iOSUITestBundlePath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"iOSAppUITestFixture" ofType:@"xctest"];
}

+ (NSString *)iOSAppTestBundlePath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"iOSAppFixtureAppTests" ofType:@"xctest"];
}

@end

@implementation XCTestCase (FBXCTestKitTests)

- (nullable NSString *)iOSUnitTestBundlePath
{
  return [self signTestBundle:FBXCTestKitFixtures.iOSUnitTestBundlePath];
}

- (nullable NSString *)iOSUITestBundlePath
{
  return [self signTestBundle:FBXCTestKitFixtures.iOSUITestBundlePath];
}

- (nullable NSString *)iOSAppTestBundlePath
{
  return [self signTestBundle:FBXCTestKitFixtures.iOSAppTestBundlePath];
}

- (nullable NSString *)signTestBundle:(NSString *)bundlePath;
{
  id<FBCodesignProvider> codesign = FBCodesignProvider.codeSignCommandWithAdHocIdentity;
  if ([[codesign cdHashForBundleAtPath:bundlePath] await:nil]) {
    return bundlePath;
  }
  NSError *error = nil;
  if ([[codesign signBundleAtPath:bundlePath] await:&error]) {
    return bundlePath;
  }
  XCTFail(@"Bundle at path %@ could not be codesigned: %@", bundlePath, error);
  return nil;
}

@end

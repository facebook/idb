/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

+ (NSString *)iOSUnitTestBundlePath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"iOSUnitTestFixture" ofType:@"xctest"];
}

+ (NSString *)macUnitTestBundlePath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"MacUnitTestFixture" ofType:@"xctest"];
}

@end

@implementation XCTestCase (FBXCTestKitTests)

- (nullable NSString *)iOSUnitTestBundlePath
{
  NSString *bundlePath = FBXCTestKitFixtures.iOSUnitTestBundlePath;
  if (!FBControlCoreGlobalConfiguration.isXcode8OrGreater) {
    return bundlePath;
  }
  id<FBCodesignProvider> codesign = FBCodesignProvider.codeSignCommandWithAdHocIdentity;
  if ([codesign cdHashForBundleAtPath:bundlePath error:nil]) {
    return bundlePath;
  }
  NSError *error = nil;
  if ([codesign signBundleAtPath:bundlePath error:&error]) {
    return bundlePath;
  }
  XCTFail(@"Bundle at path %@ could not be codesigned: %@", bundlePath, error);
  return nil;
}

@end

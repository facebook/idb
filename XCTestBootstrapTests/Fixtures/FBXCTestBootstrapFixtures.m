/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestBootstrapFixtures.h"

@implementation XCTestCase (FBXCTestBootstrapFixtures)

+ (NSBundle *)iosUnitTestBundleFixture
{
  NSString *fixturePath = [[NSBundle bundleForClass:self.class] pathForResource:@"iOSUnitTestFixture" ofType:@"xctest"];
  return [NSBundle bundleWithPath:fixturePath];
}

+ (NSBundle *)macUnitTestBundleFixture
{
  NSString *fixturePath = [[NSBundle bundleForClass:self.class] pathForResource:@"MacUnitTestFixture" ofType:@"xctest"];
  return [NSBundle bundleWithPath:fixturePath];
}

+ (NSString *)JUnitXMLResult0Path
{
  return [[NSBundle bundleForClass:self] pathForResource:@"junitResult0" ofType:@"xml"];
}

+ (NSString *)JUnitXMLResult1Path
{
  return [[NSBundle bundleForClass:self] pathForResource:@"junitResult1" ofType:@"xml"];
}

+ (NSString *)sampleXCTestRunPath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"Sample" ofType:@"xctestrun"];
}

+ (NSString *)emptyXCTestRunPath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"Empty" ofType:@"xctestrun"];
}

@end

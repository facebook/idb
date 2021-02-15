/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

@end

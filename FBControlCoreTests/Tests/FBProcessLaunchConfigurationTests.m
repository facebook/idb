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

#import "FBControlCoreFixtures.h"
#import "FBControlCoreValueTestCase.h"

@interface FBProcessLaunchConfigurationTests : FBControlCoreValueTestCase

@end

@implementation FBProcessLaunchConfigurationTests

+ (NSArray<FBApplicationLaunchConfiguration *> *)appLaunchConfigurations
{
  return @[
    [FBApplicationLaunchConfiguration configurationWithBundleID:@"com.foo.bar" bundleName:@"Foo" arguments:@[@"a", @"b"] environment:@{@"d": @"e"} output:FBProcessOutputConfiguration.defaultOutputToFile],
    [FBApplicationLaunchConfiguration configurationWithBundleID:@"com.foo.bar" bundleName:@"Foo" arguments:@[@"a", @"b"] environment:@{@"d": @"e"} output:FBProcessOutputConfiguration.outputToDevNull],
  ];
}

- (void)testValueSemantics
{
  NSArray<FBApplicationLaunchConfiguration *> *configurations = FBProcessLaunchConfigurationTests.appLaunchConfigurations;
  [self assertEqualityOfCopy:configurations];
  [self assertUnarchiving:configurations];
  [self assertJSONSerialization:configurations];
  [self assertJSONDeserialization:configurations];
}

@end

/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
    [FBApplicationLaunchConfiguration configurationWithBundleID:@"com.foo.bar" bundleName:@"Foo" arguments:@[@"a", @"b"] environment:@{@"d": @"e"} waitForDebugger:NO output:FBProcessOutputConfiguration.defaultOutputToFile],
    [FBApplicationLaunchConfiguration configurationWithBundleID:@"com.foo.bar" bundleName:@"Foo" arguments:@[@"a", @"b"] environment:@{@"d": @"e"} waitForDebugger:NO output:FBProcessOutputConfiguration.outputToDevNull],
  ];
}

- (void)testValueSemantics
{
  NSArray<FBApplicationLaunchConfiguration *> *configurations = FBProcessLaunchConfigurationTests.appLaunchConfigurations;
  [self assertEqualityOfCopy:configurations];
  [self assertJSONSerialization:configurations];
  [self assertJSONDeserialization:configurations];
}

@end

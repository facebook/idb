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
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBControlCoreValueTestCase.h"

@interface FBTestLaunchConfigurationTests : FBControlCoreValueTestCase

@end

@implementation FBTestLaunchConfigurationTests

+ (NSArray<FBTestLaunchConfiguration *> *)configurations
{
  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration configurationWithBundleID:@"com.foo.bar" bundleName:@"FooBar" arguments:@[@"aa", @"bbb"] environment:@{@"ff" : @"gg"} waitForDebugger:NO output:FBProcessOutputConfiguration.outputToDevNull];
  return @[
    [FBTestLaunchConfiguration configurationWithTestBundlePath:@"/bar/bar"],
    [[[[[FBTestLaunchConfiguration configurationWithTestBundlePath:@"/aa"] withUITesting:YES] withTestHostPath:@"/baa"] withTimeout:12] withTestsToRun:[NSSet setWithArray:@[@"foo", @"bar"]]],
    [[FBTestLaunchConfiguration configurationWithTestBundlePath:@"/bb"] withApplicationLaunchConfiguration:appLaunch],
  ];
}

- (void)testValueSemantics
{
  NSArray<FBTestLaunchConfiguration *> *configurations = FBTestLaunchConfigurationTests.configurations;
  [self assertEqualityOfCopy:configurations];
  [self assertJSONSerialization:configurations];
  [self assertJSONDeserialization:configurations];
}

@end

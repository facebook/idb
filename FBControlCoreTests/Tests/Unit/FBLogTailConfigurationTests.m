/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreValueTestCase.h"

@interface FBLogTailConfigurationTests : FBControlCoreValueTestCase

@end

@implementation FBLogTailConfigurationTests

- (void)testValueSemantics
{
  NSArray<FBLogTailConfiguration *> *configurations = @[
    [FBLogTailConfiguration configurationWithArguments:@[]],
    [FBLogTailConfiguration configurationWithArguments:@[@"foo", @"bar", @"baz"]],
  ];

  [self assertEqualityOfCopy:configurations];
  [self assertJSONSerialization:configurations];
  [self assertJSONDeserialization:configurations];
}

@end

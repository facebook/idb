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

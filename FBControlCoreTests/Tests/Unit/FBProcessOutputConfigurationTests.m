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

@interface FBProcessOutputConfigurationTests : FBControlCoreValueTestCase

@end

@implementation FBProcessOutputConfigurationTests

+ (NSArray<FBProcessOutputConfiguration *> *)configurations
{
  return @[
    FBProcessOutputConfiguration.outputToDevNull,
    FBProcessOutputConfiguration.defaultOutputToFile,
    [FBProcessOutputConfiguration configurationWithStdOut:@"/foo.txt" stdErr:@"/bar.txt" error:nil],
    [FBProcessOutputConfiguration configurationWithStdOut:FBProcessOutputToFileDefaultLocation stdErr:NSNull.null error:nil],
    [FBProcessOutputConfiguration configurationWithStdOut:NSNull.null stdErr:@"/bar.txt" error:nil],
  ];
}

- (void)testValueSemantics
{
  NSArray<FBProcessOutputConfiguration *> *configurations = FBProcessOutputConfigurationTests.configurations;
  [self assertEqualityOfCopy:configurations];
  [self assertJSONSerialization:configurations];
  [self assertJSONDeserialization:configurations];
}

@end

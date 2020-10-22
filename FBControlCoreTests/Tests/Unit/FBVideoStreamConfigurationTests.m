/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import "FBControlCoreValueTestCase.h"

@interface FBVideoStreamConfigurationTests : FBControlCoreValueTestCase

@end

@implementation FBVideoStreamConfigurationTests

- (void)testValueSemantics
{
  NSArray<FBVideoStreamConfiguration *> *configurations = @[
    [FBVideoStreamConfiguration configurationWithEncoding:FBVideoStreamEncodingBGRA framesPerSecond:@30],
    [FBVideoStreamConfiguration configurationWithEncoding:FBVideoStreamEncodingBGRA framesPerSecond:@60],
    [FBVideoStreamConfiguration configurationWithEncoding:FBVideoStreamEncodingBGRA framesPerSecond:nil],
    [FBVideoStreamConfiguration configurationWithEncoding:FBVideoStreamEncodingH264 framesPerSecond:nil],
  ];

  [self assertEqualityOfCopy:configurations];
  [self assertJSONSerialization:configurations];
  [self assertJSONDeserialization:configurations];
}

@end

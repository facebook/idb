/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import "FBControlCoreValueTestCase.h"

@interface FBBitmapStreamConfigurationTests : FBControlCoreValueTestCase

@end

@implementation FBBitmapStreamConfigurationTests

- (void)testValueSemantics
{
  NSArray<FBBitmapStreamConfiguration *> *configurations = @[
    [FBBitmapStreamConfiguration configurationWithEncoding:FBBitmapStreamEncodingBGRA framesPerSecond:@30],
    [FBBitmapStreamConfiguration configurationWithEncoding:FBBitmapStreamEncodingBGRA framesPerSecond:@60],
    [FBBitmapStreamConfiguration configurationWithEncoding:FBBitmapStreamEncodingBGRA framesPerSecond:nil],
    [FBBitmapStreamConfiguration configurationWithEncoding:FBBitmapStreamEncodingH264 framesPerSecond:nil],
  ];

  [self assertEqualityOfCopy:configurations];
  [self assertJSONSerialization:configurations];
  [self assertJSONDeserialization:configurations];
}

@end

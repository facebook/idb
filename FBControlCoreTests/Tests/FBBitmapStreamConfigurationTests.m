/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

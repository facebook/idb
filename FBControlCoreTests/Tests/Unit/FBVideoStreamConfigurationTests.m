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
    [[FBVideoStreamConfiguration alloc] initWithEncoding:FBVideoStreamEncodingBGRA framesPerSecond:@30 compressionQuality:@0.2],
    [[FBVideoStreamConfiguration alloc] initWithEncoding:FBVideoStreamEncodingBGRA framesPerSecond:@60 compressionQuality:@0.2],
    [[FBVideoStreamConfiguration alloc] initWithEncoding:FBVideoStreamEncodingBGRA framesPerSecond:nil compressionQuality:nil],
    [[FBVideoStreamConfiguration alloc] initWithEncoding:FBVideoStreamEncodingH264 framesPerSecond:nil compressionQuality:@0.2],
  ];

  [self assertEqualityOfCopy:configurations];
}

@end

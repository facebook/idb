/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBVideoStreamConfigurationTests : XCTestCase
@end

@implementation FBVideoStreamConfigurationTests

- (void)testDefaultCompressionQuality
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithEncoding:FBVideoStreamEncodingH264
    framesPerSecond:nil
    compressionQuality:nil
    scaleFactor:nil
    avgBitrate:nil
    keyFrameRate:nil];

  XCTAssertEqualObjects(config.compressionQuality, @0.2);
}

// NOTE: Default changes to @1.0 in "MPEG-TS container format" commit.
- (void)testDefaultKeyFrameRate
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithEncoding:FBVideoStreamEncodingH264
    framesPerSecond:nil
    compressionQuality:nil
    scaleFactor:nil
    avgBitrate:nil
    keyFrameRate:nil];

  XCTAssertEqualObjects(config.keyFrameRate, @10.0);
}

- (void)testExplicitValuesPreserved
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithEncoding:FBVideoStreamEncodingH264
    framesPerSecond:nil
    compressionQuality:@0.5
    scaleFactor:nil
    avgBitrate:nil
    keyFrameRate:@5.0];

  XCTAssertEqualObjects(config.compressionQuality, @0.5);
  XCTAssertEqualObjects(config.keyFrameRate, @5.0);
}

- (void)testConfigurationEquality
{
  FBVideoStreamConfiguration *a = [[FBVideoStreamConfiguration alloc]
    initWithEncoding:FBVideoStreamEncodingH264
    framesPerSecond:@30
    compressionQuality:@0.5
    scaleFactor:nil
    avgBitrate:nil
    keyFrameRate:@5.0];
  FBVideoStreamConfiguration *b = [[FBVideoStreamConfiguration alloc]
    initWithEncoding:FBVideoStreamEncodingH264
    framesPerSecond:@30
    compressionQuality:@0.5
    scaleFactor:nil
    avgBitrate:nil
    keyFrameRate:@5.0];

  XCTAssertEqualObjects(a, b);
}

- (void)testConfigurationCopy
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithEncoding:FBVideoStreamEncodingH264
    framesPerSecond:nil
    compressionQuality:nil
    scaleFactor:nil
    avgBitrate:nil
    keyFrameRate:nil];

  FBVideoStreamConfiguration *copy = [config copy];
  // Immutable object returns self on copy
  XCTAssertEqual(config, copy);
}

@end

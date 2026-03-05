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

- (void)testDefaultRateControl
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithFormat:[FBVideoStreamFormat compressedVideoWithCodec:FBVideoStreamCodecH264 transport:FBVideoStreamTransportAnnexB]
    framesPerSecond:nil
    rateControl:nil
    scaleFactor:nil
    keyFrameRate:nil];

  // Default: constant quality at 0.75
  XCTAssertEqual(config.rateControl.mode, FBVideoStreamRateControlModeConstantQuality);
  XCTAssertEqualObjects(config.rateControl.value, @0.75);
}

- (void)testDefaultKeyFrameRate
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithFormat:[FBVideoStreamFormat compressedVideoWithCodec:FBVideoStreamCodecH264 transport:FBVideoStreamTransportAnnexB]
    framesPerSecond:nil
    rateControl:nil
    scaleFactor:nil
    keyFrameRate:nil];

  XCTAssertEqualObjects(config.keyFrameRate, @1.0);
}

- (void)testExplicitQualityPreserved
{
  FBVideoStreamRateControl *rc = [FBVideoStreamRateControl quality:@0.7];
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithFormat:[FBVideoStreamFormat compressedVideoWithCodec:FBVideoStreamCodecH264 transport:FBVideoStreamTransportAnnexB]
    framesPerSecond:nil
    rateControl:rc
    scaleFactor:nil
    keyFrameRate:@5.0];

  XCTAssertEqual(config.rateControl.mode, FBVideoStreamRateControlModeConstantQuality);
  XCTAssertEqualObjects(config.rateControl.value, @0.7);
  XCTAssertEqualObjects(config.keyFrameRate, @5.0);
}

- (void)testExplicitBitratePreserved
{
  FBVideoStreamRateControl *rc = [FBVideoStreamRateControl bitrate:@500000];
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithFormat:[FBVideoStreamFormat compressedVideoWithCodec:FBVideoStreamCodecH264 transport:FBVideoStreamTransportAnnexB]
    framesPerSecond:nil
    rateControl:rc
    scaleFactor:nil
    keyFrameRate:nil];

  XCTAssertEqual(config.rateControl.mode, FBVideoStreamRateControlModeAverageBitrate);
  XCTAssertEqualObjects(config.rateControl.value, @500000);
}

- (void)testConfigurationEquality
{
  FBVideoStreamRateControl *rc = [FBVideoStreamRateControl quality:@0.5];
  FBVideoStreamConfiguration *a = [[FBVideoStreamConfiguration alloc]
    initWithFormat:[FBVideoStreamFormat compressedVideoWithCodec:FBVideoStreamCodecH264 transport:FBVideoStreamTransportAnnexB]
    framesPerSecond:@30
    rateControl:rc
    scaleFactor:nil
    keyFrameRate:@5.0];
  FBVideoStreamConfiguration *b = [[FBVideoStreamConfiguration alloc]
    initWithFormat:[FBVideoStreamFormat compressedVideoWithCodec:FBVideoStreamCodecH264 transport:FBVideoStreamTransportAnnexB]
    framesPerSecond:@30
    rateControl:[FBVideoStreamRateControl quality:@0.5]
    scaleFactor:nil
    keyFrameRate:@5.0];

  XCTAssertEqualObjects(a, b);
}

- (void)testConfigurationCopy
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithFormat:[FBVideoStreamFormat compressedVideoWithCodec:FBVideoStreamCodecH264 transport:FBVideoStreamTransportAnnexB]
    framesPerSecond:nil
    rateControl:nil
    scaleFactor:nil
    keyFrameRate:nil];

  FBVideoStreamConfiguration *copy = [config copy];
  // Immutable object returns self on copy
  XCTAssertEqual(config, copy);
}

- (void)testRateControlEquality
{
  FBVideoStreamRateControl *a = [FBVideoStreamRateControl quality:@0.5];
  FBVideoStreamRateControl *b = [FBVideoStreamRateControl quality:@0.5];
  FBVideoStreamRateControl *c = [FBVideoStreamRateControl bitrate:@500000];

  XCTAssertEqualObjects(a, b);
  XCTAssertNotEqualObjects(a, c);
}

@end

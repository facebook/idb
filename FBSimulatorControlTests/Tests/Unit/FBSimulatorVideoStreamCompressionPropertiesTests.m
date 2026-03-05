// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

#import <XCTest/XCTest.h>
#import <VideoToolbox/VideoToolbox.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

@interface FBSimulatorVideoStreamCompressionPropertiesTests : XCTestCase
@end

@implementation FBSimulatorVideoStreamCompressionPropertiesTests

#pragma mark - Shared Properties

- (void)testBasePropertiesAlwaysPresent
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithFormat:[FBVideoStreamFormat compressedVideoWithCodec:FBVideoStreamCodecH264 transport:FBVideoStreamTransportAnnexB]
    framesPerSecond:nil
    rateControl:nil
    scaleFactor:nil
    keyFrameRate:nil];
  NSDictionary *props = [FBSimulatorVideoStream compressionSessionPropertiesForConfiguration:config callerProperties:@{}];
  XCTAssertEqualObjects(props[(NSString *)kVTCompressionPropertyKey_RealTime], @YES);
  XCTAssertEqualObjects(props[(NSString *)kVTCompressionPropertyKey_AllowFrameReordering], @NO);
  // No rateControl set: quality mode with default 0.75
  XCTAssertEqualObjects(props[(NSString *)kVTCompressionPropertyKey_Quality], @0.75);
  XCTAssertNil(props[(NSString *)kVTCompressionPropertyKey_AverageBitRate]);
  XCTAssertEqualObjects(props[(NSString *)kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration], @1.0);
}

- (void)testCallerPropertiesMerged
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithFormat:[FBVideoStreamFormat mjpeg]
    framesPerSecond:nil
    rateControl:nil
    scaleFactor:nil
    keyFrameRate:nil];
  NSDictionary *callerProps = @{@"CustomKey": @42};
  NSDictionary *props = [FBSimulatorVideoStream compressionSessionPropertiesForConfiguration:config callerProperties:callerProps];
  XCTAssertEqualObjects(props[@"CustomKey"], @42);
}

#pragma mark - Compression Quality

- (void)testMJPEGCompressionPropertiesContainQuality
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithFormat:[FBVideoStreamFormat mjpeg]
    framesPerSecond:nil
    rateControl:[FBVideoStreamRateControl quality:@0.5]
    scaleFactor:nil
    keyFrameRate:nil];
  NSDictionary *props = [FBSimulatorVideoStream compressionSessionPropertiesForConfiguration:config callerProperties:@{}];
  XCTAssertEqualObjects(props[(NSString *)kVTCompressionPropertyKey_Quality], @0.5);
}

- (void)testMinicapCompressionPropertiesContainQuality
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithFormat:[FBVideoStreamFormat minicap]
    framesPerSecond:nil
    rateControl:[FBVideoStreamRateControl quality:@0.5]
    scaleFactor:nil
    keyFrameRate:nil];
  NSDictionary *props = [FBSimulatorVideoStream compressionSessionPropertiesForConfiguration:config callerProperties:@{}];
  XCTAssertEqualObjects(props[(NSString *)kVTCompressionPropertyKey_Quality], @0.5);
}

- (void)testH264CompressionPropertiesContainQuality
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithFormat:[FBVideoStreamFormat compressedVideoWithCodec:FBVideoStreamCodecH264 transport:FBVideoStreamTransportAnnexB]
    framesPerSecond:nil
    rateControl:[FBVideoStreamRateControl quality:@0.5]
    scaleFactor:nil
    keyFrameRate:nil];
  NSDictionary *props = [FBSimulatorVideoStream compressionSessionPropertiesForConfiguration:config callerProperties:@{}];
  XCTAssertEqualObjects(props[(NSString *)kVTCompressionPropertyKey_Quality], @0.5);
}

#pragma mark - H264 Encoding-Specific Properties

- (void)testH264ProfileAndEntropyMode
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithFormat:[FBVideoStreamFormat compressedVideoWithCodec:FBVideoStreamCodecH264 transport:FBVideoStreamTransportAnnexB]
    framesPerSecond:nil
    rateControl:nil
    scaleFactor:nil
    keyFrameRate:nil];
  NSDictionary *props = [FBSimulatorVideoStream compressionSessionPropertiesForConfiguration:config callerProperties:@{}];
  XCTAssertNotNil(props[(NSString *)kVTCompressionPropertyKey_ProfileLevel]);
  XCTAssertNotNil(props[(NSString *)kVTCompressionPropertyKey_H264EntropyMode]);
}

#pragma mark - Bitrate Configuration

- (void)testExplicitBitrate
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithFormat:[FBVideoStreamFormat mjpeg]
    framesPerSecond:nil
    rateControl:[FBVideoStreamRateControl bitrate:@500000]
    scaleFactor:nil
    keyFrameRate:nil];
  NSDictionary *props = [FBSimulatorVideoStream compressionSessionPropertiesForConfiguration:config callerProperties:@{}];
  XCTAssertEqualObjects(props[(NSString *)kVTCompressionPropertyKey_AverageBitRate], @500000);
}

@end

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
    initWithEncoding:FBVideoStreamEncodingH264
    framesPerSecond:nil
    compressionQuality:nil
    scaleFactor:nil
    avgBitrate:nil
    keyFrameRate:nil];
  NSDictionary *props = [FBSimulatorVideoStream compressionSessionPropertiesForConfiguration:config callerProperties:@{}];
  XCTAssertEqualObjects(props[(NSString *)kVTCompressionPropertyKey_RealTime], @YES);
  XCTAssertEqualObjects(props[(NSString *)kVTCompressionPropertyKey_AllowFrameReordering], @NO);
  XCTAssertNotNil(props[(NSString *)kVTCompressionPropertyKey_AverageBitRate]);
  XCTAssertNotNil(props[(NSString *)kVTCompressionPropertyKey_DataRateLimits]);
  XCTAssertEqualObjects(props[(NSString *)kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration], @10.0);
}

- (void)testCallerPropertiesMerged
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithEncoding:FBVideoStreamEncodingMJPEG
    framesPerSecond:nil
    compressionQuality:nil
    scaleFactor:nil
    avgBitrate:nil
    keyFrameRate:nil];
  NSDictionary *callerProps = @{@"CustomKey": @42};
  NSDictionary *props = [FBSimulatorVideoStream compressionSessionPropertiesForConfiguration:config callerProperties:callerProps];
  XCTAssertEqualObjects(props[@"CustomKey"], @42);
}

#pragma mark - Compression Quality

- (void)testMJPEGCompressionPropertiesContainQuality
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithEncoding:FBVideoStreamEncodingMJPEG
    framesPerSecond:nil
    compressionQuality:@0.5
    scaleFactor:nil
    avgBitrate:nil
    keyFrameRate:nil];
  NSDictionary *props = [FBSimulatorVideoStream compressionSessionPropertiesForConfiguration:config callerProperties:@{}];
  XCTAssertEqualObjects(props[(NSString *)kVTCompressionPropertyKey_Quality], @0.5);
}

- (void)testMinicapCompressionPropertiesContainQuality
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithEncoding:FBVideoStreamEncodingMinicap
    framesPerSecond:nil
    compressionQuality:@0.5
    scaleFactor:nil
    avgBitrate:nil
    keyFrameRate:nil];
  NSDictionary *props = [FBSimulatorVideoStream compressionSessionPropertiesForConfiguration:config callerProperties:@{}];
  XCTAssertEqualObjects(props[(NSString *)kVTCompressionPropertyKey_Quality], @0.5);
}

- (void)testH264CompressionPropertiesDoNotContainQuality
{
  // BUG: H264 should get compression quality but currently doesn't.
  // Quality is only applied to MJPEG and Minicap encodings.
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithEncoding:FBVideoStreamEncodingH264
    framesPerSecond:nil
    compressionQuality:@0.5
    scaleFactor:nil
    avgBitrate:nil
    keyFrameRate:nil];
  NSDictionary *props = [FBSimulatorVideoStream compressionSessionPropertiesForConfiguration:config callerProperties:@{}];
  XCTAssertNil(props[(NSString *)kVTCompressionPropertyKey_Quality],
    @"H264 does not apply compression quality (bug: quality is only applied to MJPEG and Minicap)");
}

#pragma mark - H264 Encoding-Specific Properties

- (void)testH264ProfileAndEntropyMode
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithEncoding:FBVideoStreamEncodingH264
    framesPerSecond:nil
    compressionQuality:nil
    scaleFactor:nil
    avgBitrate:nil
    keyFrameRate:nil];
  NSDictionary *props = [FBSimulatorVideoStream compressionSessionPropertiesForConfiguration:config callerProperties:@{}];
  XCTAssertNotNil(props[(NSString *)kVTCompressionPropertyKey_ProfileLevel]);
  XCTAssertNotNil(props[(NSString *)kVTCompressionPropertyKey_H264EntropyMode]);
}

#pragma mark - Bitrate Configuration

- (void)testExplicitBitrate
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithEncoding:FBVideoStreamEncodingMJPEG
    framesPerSecond:nil
    compressionQuality:nil
    scaleFactor:nil
    avgBitrate:@500000
    keyFrameRate:nil];
  NSDictionary *props = [FBSimulatorVideoStream compressionSessionPropertiesForConfiguration:config callerProperties:@{}];
  XCTAssertEqualObjects(props[(NSString *)kVTCompressionPropertyKey_AverageBitRate], @500000);
}

@end

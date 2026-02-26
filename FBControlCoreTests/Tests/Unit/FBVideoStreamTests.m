/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>
#import <CoreMedia/CoreMedia.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreLoggerDouble.h"

#pragma mark - Test Doubles

/**
 A test double conforming to FBDataConsumerAsync with a controllable unprocessedDataCount.
 Used to test checkConsumerBufferLimit overflow behavior.
 */
@interface FBOverflownConsumerDouble : NSObject <FBDataConsumer, FBDataConsumerAsync>

@property (nonatomic, assign) NSInteger unprocessedDataCount;

@end

@implementation FBOverflownConsumerDouble

- (void)consumeData:(NSData *)data {}
- (void)consumeEndOfFile {}

@end

#pragma mark - Helpers

static CMSampleBufferRef CreateH264SampleBuffer(BOOL isKeyFrame)
{
  // H264 SPS and PPS parameter sets
  const uint8_t sps[] = {0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2};
  const uint8_t pps[] = {0x68, 0xce, 0x38, 0x80};
  const uint8_t *paramSets[] = {sps, pps};
  size_t paramSizes[] = {sizeof(sps), sizeof(pps)};

  CMFormatDescriptionRef formatDesc = NULL;
  OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
    NULL, 2, paramSets, paramSizes, 4, &formatDesc);
  NSCAssert(status == noErr, @"Failed to create H264 format description: %d", (int)status);

  // AVCC NAL data: [4-byte big-endian length][NAL bytes]
  static uint8_t avccData[] = {
    0x00, 0x00, 0x00, 0x05,            // NAL length = 5
    0x65, 0x88, 0x80, 0x40, 0x00       // fake IDR slice
  };

  CMBlockBufferRef blockBuf = NULL;
  status = CMBlockBufferCreateWithMemoryBlock(
    NULL, avccData, sizeof(avccData), kCFAllocatorNull,
    NULL, 0, sizeof(avccData), 0, &blockBuf);
  NSCAssert(status == noErr, @"Failed to create block buffer: %d", (int)status);

  CMSampleBufferRef sampleBuf = NULL;
  size_t sampleSize = sizeof(avccData);
  CMSampleTimingInfo timing = {
    .duration = CMTimeMake(1, 30),
    .presentationTimeStamp = CMTimeMake(0, 90000),
    .decodeTimeStamp = kCMTimeInvalid
  };
  status = CMSampleBufferCreate(
    NULL, blockBuf, true, NULL, NULL, formatDesc,
    1, 1, &timing, 1, &sampleSize, &sampleBuf);
  NSCAssert(status == noErr, @"Failed to create sample buffer: %d", (int)status);

  // Set attachments for keyframe/non-keyframe.
  // For keyframes: NotSync is absent (modern VideoToolbox pattern).
  // For non-keyframes: NotSync = kCFBooleanTrue.
  CFMutableDictionaryRef attachments = (CFMutableDictionaryRef)
    CFArrayGetValueAtIndex(
      CMSampleBufferGetSampleAttachmentsArray(sampleBuf, true), 0);
  if (!isKeyFrame) {
    CFDictionarySetValue(attachments,
      kCMSampleAttachmentKey_NotSync, kCFBooleanTrue);
  }

  CFRelease(formatDesc);
  CFRelease(blockBuf);

  return sampleBuf;
}

#pragma mark - Tests

@interface FBVideoStreamTests : XCTestCase
@end

@implementation FBVideoStreamTests

#pragma mark H264 Annex-B Writer

// BUG: Modern VideoToolbox encoders omit DependsOnOthers. The current code checks
// DependsOnOthers == kCFBooleanFalse, which returns NULL here, so keyframe is not
// detected and parameter sets are not emitted. Fixed in "Modernize H264 Annex-B writer".
- (void)testH264AnnexBKeyframeDetectionWithModernAttachments
{
  CMSampleBufferRef sampleBuffer = CreateH264SampleBuffer(YES);
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  id<FBControlCoreLogger> logger = [[FBControlCoreLoggerDouble alloc] init];
  NSError *error = nil;

  BOOL result = WriteFrameToAnnexBStream(sampleBuffer, consumer, logger, &error);
  XCTAssertTrue(result);
  XCTAssertNil(error);

  NSData *output = consumer.data;

  // SPS bytes that would appear if keyframe were detected
  const uint8_t sps[] = {0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2};
  NSData *spsData = [NSData dataWithBytes:sps length:sizeof(sps)];

  // BUG: Keyframe is NOT detected, so output does NOT contain SPS+PPS.
  // Output is only: [start_code][NAL data]
  NSRange spsRange = [output rangeOfData:spsData options:0 range:NSMakeRange(0, output.length)];
  XCTAssertEqual(spsRange.location, (NSUInteger)NSNotFound, @"SPS should NOT be present (bug: keyframe not detected)");

  // Verify output starts with start code followed by NAL data
  const uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01};
  NSData *startCodeData = [NSData dataWithBytes:startCode length:sizeof(startCode)];
  XCTAssertTrue(output.length > 0);
  NSData *firstFourBytes = [output subdataWithRange:NSMakeRange(0, 4)];
  XCTAssertEqualObjects(firstFourBytes, startCodeData);

  CFRelease(sampleBuffer);
}

- (void)testH264AnnexBNonKeyframeEmitsNoParameterSets
{
  CMSampleBufferRef sampleBuffer = CreateH264SampleBuffer(NO);
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  id<FBControlCoreLogger> logger = [[FBControlCoreLoggerDouble alloc] init];
  NSError *error = nil;

  BOOL result = WriteFrameToAnnexBStream(sampleBuffer, consumer, logger, &error);
  XCTAssertTrue(result);
  XCTAssertNil(error);

  NSData *output = consumer.data;

  // SPS bytes
  const uint8_t sps[] = {0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2};
  NSData *spsData = [NSData dataWithBytes:sps length:sizeof(sps)];

  // Non-keyframe should never contain SPS/PPS
  NSRange spsRange = [output rangeOfData:spsData options:0 range:NSMakeRange(0, output.length)];
  XCTAssertEqual(spsRange.location, (NSUInteger)NSNotFound, @"SPS should not be present for non-keyframe");

  // Should still contain NAL data with start code
  const uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01};
  NSData *startCodeData = [NSData dataWithBytes:startCode length:sizeof(startCode)];
  XCTAssertTrue(output.length > 0);
  NSData *firstFourBytes = [output subdataWithRange:NSMakeRange(0, 4)];
  XCTAssertEqualObjects(firstFourBytes, startCodeData);

  CFRelease(sampleBuffer);
}

- (void)testH264AnnexBAVCCToAnnexBConversion
{
  CMSampleBufferRef sampleBuffer = CreateH264SampleBuffer(NO);
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  id<FBControlCoreLogger> logger = [[FBControlCoreLoggerDouble alloc] init];
  NSError *error = nil;

  BOOL result = WriteFrameToAnnexBStream(sampleBuffer, consumer, logger, &error);
  XCTAssertTrue(result);
  XCTAssertNil(error);

  NSData *output = consumer.data;

  // Expected: [00 00 00 01][65 88 80 40 00] (start code + NAL data, no AVCC length prefix)
  const uint8_t expected[] = {
    0x00, 0x00, 0x00, 0x01,            // Annex-B start code
    0x65, 0x88, 0x80, 0x40, 0x00       // NAL unit data
  };
  NSData *expectedData = [NSData dataWithBytes:expected length:sizeof(expected)];
  XCTAssertEqualObjects(output, expectedData);

  CFRelease(sampleBuffer);
}

#pragma mark Minicap Header

- (void)testWriteMinicapHeader
{
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  id<FBControlCoreLogger> logger = [[FBControlCoreLoggerDouble alloc] init];
  NSError *error = nil;

  BOOL result = WriteMinicapHeaderToStream(1920, 1080, consumer, logger, &error);
  XCTAssertTrue(result);
  XCTAssertNil(error);

  NSData *output = consumer.data;
  XCTAssertEqual(output.length, 24u);

  const uint8_t *bytes = output.bytes;

  // version = 1
  XCTAssertEqual(bytes[0], 1);
  // headerSize = 24
  XCTAssertEqual(bytes[1], 24);

  // displayWidth = 1920 in little-endian at offset 6
  uint32_t width;
  memcpy(&width, &bytes[6], sizeof(uint32_t));
  width = OSSwapLittleToHostInt32(width);
  XCTAssertEqual(width, 1920u);

  // displayHeight = 1080 in little-endian at offset 10
  uint32_t height;
  memcpy(&height, &bytes[10], sizeof(uint32_t));
  height = OSSwapLittleToHostInt32(height);
  XCTAssertEqual(height, 1080u);
}

#pragma mark Buffer Limit

- (void)testCheckConsumerBufferLimitAllowsWhenNotOverflown
{
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  id<FBControlCoreLogger> logger = [[FBControlCoreLoggerDouble alloc] init];

  // FBAccumulatingBuffer does not conform to FBDataConsumerAsync,
  // so checkConsumerBufferLimit always returns YES.
  XCTAssertTrue(checkConsumerBufferLimit(consumer, logger));
}

- (void)testCheckConsumerBufferLimitDropsWhenOverflown
{
  FBOverflownConsumerDouble *consumer = [[FBOverflownConsumerDouble alloc] init];
  id<FBControlCoreLogger> logger = [[FBControlCoreLoggerDouble alloc] init];

  // With unprocessedDataCount = 0, should allow
  consumer.unprocessedDataCount = 0;
  XCTAssertTrue(checkConsumerBufferLimit(consumer, logger));

  // MaxAllowedUnprocessedDataCounts is 2; > 2 triggers drop
  consumer.unprocessedDataCount = 3;
  XCTAssertFalse(checkConsumerBufferLimit(consumer, logger));
}

@end

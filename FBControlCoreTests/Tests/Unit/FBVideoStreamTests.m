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

static CMSampleBufferRef CreateNotReadySampleBuffer(void)
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
  // Pass false for dataReady to create a not-ready buffer
  status = CMSampleBufferCreate(
    NULL, blockBuf, false, NULL, NULL, formatDesc,
    1, 1, &timing, 1, &sampleSize, &sampleBuf);
  NSCAssert(status == noErr, @"Failed to create sample buffer: %d", (int)status);

  CFRelease(formatDesc);
  CFRelease(blockBuf);

  return sampleBuf;
}

#pragma mark - Tests

@interface FBVideoStreamTests : XCTestCase
@end

@implementation FBVideoStreamTests

#pragma mark H264 Annex-B Writer

- (void)testH264AnnexBKeyframeDetectionWithModernAttachments
{
  CMSampleBufferRef sampleBuffer = CreateH264SampleBuffer(YES);
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  id<FBControlCoreLogger> logger = [[FBControlCoreLoggerDouble alloc] init];
  NSError *error = nil;

  BOOL result = WriteFrameToAnnexBStream(sampleBuffer, nil, consumer, logger, &error);
  XCTAssertTrue(result);
  XCTAssertNil(error);

  NSData *output = consumer.data;

  const uint8_t sps[] = {0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2};
  NSData *spsData = [NSData dataWithBytes:sps length:sizeof(sps)];
  const uint8_t pps[] = {0x68, 0xce, 0x38, 0x80};
  NSData *ppsData = [NSData dataWithBytes:pps length:sizeof(pps)];

  // Keyframe IS detected: output contains SPS+PPS before NAL data.
  // Expected: [start_code][SPS][start_code][PPS][start_code][NAL]
  NSRange spsRange = [output rangeOfData:spsData options:0 range:NSMakeRange(0, output.length)];
  XCTAssertNotEqual(spsRange.location, (NSUInteger)NSNotFound, @"SPS should be present for keyframe");
  NSRange ppsRange = [output rangeOfData:ppsData options:0 range:NSMakeRange(0, output.length)];
  XCTAssertNotEqual(ppsRange.location, (NSUInteger)NSNotFound, @"PPS should be present for keyframe");

  // SPS should come before PPS
  XCTAssertTrue(spsRange.location < ppsRange.location);

  // Verify output starts with start code
  const uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01};
  NSData *startCodeData = [NSData dataWithBytes:startCode length:sizeof(startCode)];
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

  BOOL result = WriteFrameToAnnexBStream(sampleBuffer, nil, consumer, logger, &error);
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

  BOOL result = WriteFrameToAnnexBStream(sampleBuffer, nil, consumer, logger, &error);
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

- (void)testH264AnnexBNotReadyBufferReturnsError
{
  CMSampleBufferRef sampleBuffer = CreateNotReadySampleBuffer();
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  id<FBControlCoreLogger> logger = [[FBControlCoreLoggerDouble alloc] init];
  NSError *error = nil;

  BOOL result = WriteFrameToAnnexBStream(sampleBuffer, nil, consumer, logger, &error);
  XCTAssertFalse(result);
  XCTAssertNotNil(error);
  XCTAssertTrue([error.localizedDescription containsString:@"Sample Buffer is not ready"]);
  XCTAssertEqual(consumer.data.length, 0u, @"No data should be written for not-ready buffer");

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

#pragma mark MPEG-TS CRC32

- (void)testMPEGTSCRC32KnownVector
{
  // MPEG-2 CRC32 of "123456789" is a well-known test vector
  const uint8_t data[] = {'1', '2', '3', '4', '5', '6', '7', '8', '9'};
  uint32_t crc = FBMPEGTS_CRC32(data, sizeof(data));
  XCTAssertEqual(crc, (uint32_t)0x0376E6E7);
}

- (void)testMPEGTSCRC32EmptyInput
{
  uint32_t crc = FBMPEGTS_CRC32(NULL, 0);
  XCTAssertEqual(crc, (uint32_t)0xFFFFFFFF);
}

#pragma mark MPEG-TS PAT/PMT Structure

- (void)testPATPacketStructure
{
  uint8_t counter = 0;
  NSData *pat = FBMPEGTSCreatePATPacket(&counter);

  XCTAssertEqual(pat.length, 188u);

  const uint8_t *bytes = pat.bytes;

  // Sync byte
  XCTAssertEqual(bytes[0], 0x47);

  // PID = 0x0000 (PAT), payload_unit_start = 1
  uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
  XCTAssertEqual(pid, (uint16_t)0x0000);
  XCTAssertTrue(bytes[1] & 0x40); // payload_unit_start

  // Pointer field
  XCTAssertEqual(bytes[4], 0x00);

  // table_id = 0x00 (PAT)
  XCTAssertEqual(bytes[5], 0x00);

  // Program number = 1 at section offset 8-9
  uint8_t *section = (uint8_t *)&bytes[5];
  uint16_t programNumber = (section[8] << 8) | section[9];
  XCTAssertEqual(programNumber, (uint16_t)1);

  // PMT PID = 0x0100 at section offset 10-11
  uint16_t pmtPid = ((section[10] & 0x1F) << 8) | section[11];
  XCTAssertEqual(pmtPid, (uint16_t)0x0100);

  // Continuity counter incremented
  XCTAssertEqual(counter, 1);
}

- (void)testPMTPacketStructureHEVC
{
  uint8_t counter = 0;
  NSData *pmt = FBMPEGTSCreatePMTPacket(&counter, 0x24);

  XCTAssertEqual(pmt.length, 188u);

  const uint8_t *bytes = pmt.bytes;

  // Sync byte
  XCTAssertEqual(bytes[0], 0x47);

  // PID = 0x0100 (PMT), payload_unit_start = 1
  uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
  XCTAssertEqual(pid, (uint16_t)0x0100);
  XCTAssertTrue(bytes[1] & 0x40); // payload_unit_start

  // table_id = 0x02 (PMT)
  XCTAssertEqual(bytes[5], 0x02);

  // Stream entry: stream_type = 0x24 (HEVC) at section offset 12
  uint8_t *section = (uint8_t *)&bytes[5];
  XCTAssertEqual(section[12], 0x24);

  // Elementary PID = 0x0101 at section offset 13-14
  uint16_t elementaryPid = ((section[13] & 0x1F) << 8) | section[14];
  XCTAssertEqual(elementaryPid, (uint16_t)0x0101);

  // Continuity counter incremented
  XCTAssertEqual(counter, 1);
}

- (void)testPATContinuityCounterIncrements
{
  uint8_t counter = 0;
  FBMPEGTSCreatePATPacket(&counter);
  XCTAssertEqual(counter, 1);
  FBMPEGTSCreatePATPacket(&counter);
  XCTAssertEqual(counter, 2);
}

- (void)testPMTPacketStructureH264
{
  uint8_t counter = 0;
  NSData *pmt = FBMPEGTSCreatePMTPacket(&counter, 0x1B);

  XCTAssertEqual(pmt.length, 188u);

  const uint8_t *bytes = pmt.bytes;

  // Sync byte
  XCTAssertEqual(bytes[0], 0x47);

  // PID = 0x0100 (PMT), payload_unit_start = 1
  uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
  XCTAssertEqual(pid, (uint16_t)0x0100);
  XCTAssertTrue(bytes[1] & 0x40); // payload_unit_start

  // table_id = 0x02 (PMT)
  XCTAssertEqual(bytes[5], 0x02);

  // Stream entry: stream_type = 0x1B (H264) at section offset 12
  uint8_t *section = (uint8_t *)&bytes[5];
  XCTAssertEqual(section[12], 0x1B);

  // Elementary PID = 0x0101 at section offset 13-14
  uint16_t elementaryPid = ((section[13] & 0x1F) << 8) | section[14];
  XCTAssertEqual(elementaryPid, (uint16_t)0x0101);

  // Continuity counter incremented
  XCTAssertEqual(counter, 1);
}

#pragma mark MPEG-TS Packetization

- (void)testTSPacketizationSinglePacket
{
  // Small PES payload that fits in one TS packet (< 184 bytes)
  uint8_t pesBytes[100];
  memset(pesBytes, 0xAB, sizeof(pesBytes));
  NSData *pesData = [NSData dataWithBytes:pesBytes length:sizeof(pesBytes)];

  uint8_t videoCC = 0, patCC = 0, pmtCC = 0;
  NSData *output = FBMPEGTSPacketizePES(pesData, NO, 0x24, 90000, &videoCC, &patCC, &pmtCC);

  // Non-keyframe: no PAT/PMT, just one video TS packet
  XCTAssertEqual(output.length, 188u);

  const uint8_t *bytes = output.bytes;

  // Sync byte
  XCTAssertEqual(bytes[0], 0x47);

  // payload_unit_start = 1 (first packet)
  XCTAssertTrue(bytes[1] & 0x40);

  // Video PID = 0x0101
  uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
  XCTAssertEqual(pid, (uint16_t)0x0101);

  // First packet should have adaptation field with PCR
  XCTAssertEqual(bytes[3] & 0x30, 0x30); // adaptation + payload
  XCTAssertTrue(bytes[5] & 0x10); // PCR flag set
}

- (void)testTSPacketizationMultiplePackets
{
  // PES payload > 184 bytes to require multiple TS packets
  uint8_t pesBytes[300];
  memset(pesBytes, 0xCD, sizeof(pesBytes));
  NSData *pesData = [NSData dataWithBytes:pesBytes length:sizeof(pesBytes)];

  uint8_t videoCC = 0, patCC = 0, pmtCC = 0;
  NSData *output = FBMPEGTSPacketizePES(pesData, NO, 0x24, 90000, &videoCC, &patCC, &pmtCC);

  // Should produce 2 TS packets (188 * 2 = 376)
  XCTAssertEqual(output.length, 188u * 2);

  const uint8_t *bytes = output.bytes;

  // First packet: payload_unit_start = 1
  XCTAssertEqual(bytes[0], 0x47);
  XCTAssertTrue(bytes[1] & 0x40);

  // Second packet: payload_unit_start = 0
  XCTAssertEqual(bytes[188], 0x47);
  XCTAssertFalse(bytes[189] & 0x40);
}

- (void)testTSPacketizationKeyframeEmitsPATAndPMT
{
  uint8_t pesBytes[50];
  memset(pesBytes, 0xEF, sizeof(pesBytes));
  NSData *pesData = [NSData dataWithBytes:pesBytes length:sizeof(pesBytes)];

  uint8_t videoCC = 0, patCC = 0, pmtCC = 0;
  NSData *output = FBMPEGTSPacketizePES(pesData, YES, 0x24, 90000, &videoCC, &patCC, &pmtCC);

  // Keyframe: PAT + PMT + 1 video packet = 3 * 188 = 564
  XCTAssertEqual(output.length, 188u * 3);

  const uint8_t *bytes = output.bytes;

  // First packet is PAT (PID = 0x0000)
  XCTAssertEqual(bytes[0], 0x47);
  uint16_t pid0 = ((bytes[1] & 0x1F) << 8) | bytes[2];
  XCTAssertEqual(pid0, (uint16_t)0x0000);

  // Second packet is PMT (PID = 0x0100)
  XCTAssertEqual(bytes[188], 0x47);
  uint16_t pid1 = ((bytes[189] & 0x1F) << 8) | bytes[190];
  XCTAssertEqual(pid1, (uint16_t)0x0100);

  // Third packet is video (PID = 0x0101)
  XCTAssertEqual(bytes[376], 0x47);
  uint16_t pid2 = ((bytes[377] & 0x1F) << 8) | bytes[378];
  XCTAssertEqual(pid2, (uint16_t)0x0101);
}

- (void)testTSPacketizationNonKeyframeNoPATOrPMT
{
  uint8_t pesBytes[50];
  memset(pesBytes, 0xEF, sizeof(pesBytes));
  NSData *pesData = [NSData dataWithBytes:pesBytes length:sizeof(pesBytes)];

  uint8_t videoCC = 0, patCC = 0, pmtCC = 0;
  NSData *output = FBMPEGTSPacketizePES(pesData, NO, 0x24, 90000, &videoCC, &patCC, &pmtCC);

  // Non-keyframe: just 1 video packet
  XCTAssertEqual(output.length, 188u);

  const uint8_t *bytes = output.bytes;

  // First (and only) packet is video (PID = 0x0101), not PAT/PMT
  uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
  XCTAssertEqual(pid, (uint16_t)0x0101);

  // PAT and PMT counters should not have been incremented
  XCTAssertEqual(patCC, 0);
  XCTAssertEqual(pmtCC, 0);
}

- (void)testTSPacketizationKeyframeUsesH264StreamType
{
  uint8_t pesBytes[50];
  memset(pesBytes, 0xEF, sizeof(pesBytes));
  NSData *pesData = [NSData dataWithBytes:pesBytes length:sizeof(pesBytes)];

  uint8_t videoCC = 0, patCC = 0, pmtCC = 0;
  NSData *output = FBMPEGTSPacketizePES(pesData, YES, 0x1B, 90000, &videoCC, &patCC, &pmtCC);

  // Keyframe: PAT + PMT + 1 video packet = 3 * 188 = 564
  XCTAssertEqual(output.length, 188u * 3);

  const uint8_t *bytes = output.bytes;

  // Second packet is PMT (PID = 0x0100)
  XCTAssertEqual(bytes[188], 0x47);

  // Verify PMT contains H264 stream type (0x1B) in the stream entry
  uint8_t *pmtSection = (uint8_t *)&bytes[188 + 5];
  XCTAssertEqual(pmtSection[12], 0x1B);
}

#pragma mark MPEG-TS PMT with Metadata

- (void)testPMTWithMetadataStreamContainsTwoEntries
{
  uint8_t counter = 0;
  NSData *pmt = FBMPEGTSCreatePMTPacketWithMetadata(&counter, 0x24, YES);

  XCTAssertEqual(pmt.length, 188u);

  const uint8_t *bytes = pmt.bytes;

  // Sync byte and PID = 0x0100
  XCTAssertEqual(bytes[0], 0x47);
  uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
  XCTAssertEqual(pid, (uint16_t)0x0100);

  // table_id = 0x02 (PMT)
  XCTAssertEqual(bytes[5], 0x02);

  uint8_t *section = (uint8_t *)&bytes[5];

  // Video stream entry at offset 12: stream_type = 0x24
  XCTAssertEqual(section[12], 0x24);
  uint16_t videoPid = ((section[13] & 0x1F) << 8) | section[14];
  XCTAssertEqual(videoPid, (uint16_t)0x0101);

  // Metadata stream entry at offset 17: stream_type = 0x15
  XCTAssertEqual(section[17], 0x15);
  uint16_t metaPid = ((section[18] & 0x1F) << 8) | section[19];
  XCTAssertEqual(metaPid, FBMPEGTSMetadataPID);
}

- (void)testPMTWithoutMetadataStreamUnchanged
{
  uint8_t counter1 = 0, counter2 = 0;
  NSData *pmtWithout = FBMPEGTSCreatePMTPacketWithMetadata(&counter1, 0x24, NO);
  NSData *pmtOriginal = FBMPEGTSCreatePMTPacket(&counter2, 0x24);

  XCTAssertEqualObjects(pmtWithout, pmtOriginal);
}

#pragma mark MPEG-TS Timed Metadata Packets

- (void)testTimedMetadataPacketStructure
{
  uint8_t counter = 0;
  NSData *output = FBMPEGTSCreateTimedMetadataPackets(@"Chapter 1", 90000, &counter);

  XCTAssertGreaterThan(output.length, 0u);
  XCTAssertEqual(output.length % 188, 0u);

  const uint8_t *bytes = output.bytes;

  // Sync byte
  XCTAssertEqual(bytes[0], 0x47);

  // payload_unit_start = 1
  XCTAssertTrue(bytes[1] & 0x40);

  // PID = MetadataPID (0x0102)
  uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
  XCTAssertEqual(pid, FBMPEGTSMetadataPID);

  // Continuity counter incremented
  XCTAssertEqual(counter, 1);

  // Find PES start code with private_stream_1 (0xBD)
  NSData *pesStartCode = [NSData dataWithBytes:(uint8_t[]){0x00, 0x00, 0x01, 0xBD} length:4];
  NSRange pesRange = [output rangeOfData:pesStartCode options:0 range:NSMakeRange(0, output.length)];
  XCTAssertNotEqual(pesRange.location, (NSUInteger)NSNotFound, @"PES start code with private_stream_1 should be present");

  // Find ID3 header
  NSData *id3Header = [NSData dataWithBytes:(uint8_t[]){'I', 'D', '3'} length:3];
  NSRange id3Range = [output rangeOfData:id3Header options:0 range:NSMakeRange(0, output.length)];
  XCTAssertNotEqual(id3Range.location, (NSUInteger)NSNotFound, @"ID3 header should be present");

  // Find TXXX frame
  NSData *txxxFrame = [NSData dataWithBytes:(uint8_t[]){'T', 'X', 'X', 'X'} length:4];
  NSRange txxxRange = [output rangeOfData:txxxFrame options:0 range:NSMakeRange(0, output.length)];
  XCTAssertNotEqual(txxxRange.location, (NSUInteger)NSNotFound, @"TXXX frame should be present");

  // Find the chapter text
  NSData *chapterText = [@"Chapter 1" dataUsingEncoding:NSUTF8StringEncoding];
  NSRange textRange = [output rangeOfData:chapterText options:0 range:NSMakeRange(0, output.length)];
  XCTAssertNotEqual(textRange.location, (NSUInteger)NSNotFound, @"Chapter text should be present in output");
}

- (void)testTimedMetadataShortTextFitsInOnePacket
{
  uint8_t counter = 0;
  NSData *output = FBMPEGTSCreateTimedMetadataPackets(@"Hi", 0, &counter);
  XCTAssertEqual(output.length, 188u);
}

- (void)testTimedMetadataLongTextSpansMultiplePackets
{
  NSMutableString *longText = [NSMutableString string];
  for (int i = 0; i < 50; i++) {
    [longText appendString:@"ABCDEFGHIJ"];
  }
  uint8_t counter = 0;
  NSData *output = FBMPEGTSCreateTimedMetadataPackets(longText, 45000, &counter);
  XCTAssertGreaterThan(output.length, 188u);
  XCTAssertEqual(output.length % 188, 0u);

  const uint8_t *bytes = output.bytes;
  size_t numPackets = output.length / 188;
  for (size_t i = 0; i < numPackets; i++) {
    XCTAssertEqual(bytes[i * 188], 0x47, @"Packet %zu should have sync byte", i);
    uint16_t pktPid = ((bytes[i * 188 + 1] & 0x1F) << 8) | bytes[i * 188 + 2];
    XCTAssertEqual(pktPid, FBMPEGTSMetadataPID, @"Packet %zu should have metadata PID", i);
  }

  XCTAssertTrue(bytes[1] & 0x40, @"First packet should have payload_unit_start");
  if (numPackets > 1) {
    XCTAssertFalse(bytes[189] & 0x40, @"Second packet should not have payload_unit_start");
  }
}

#pragma mark fMP4 Writer

- (void)testFMP4InitSegmentEmittedOnFirstKeyframe
{
  CMSampleBufferRef sampleBuffer = CreateH264SampleBuffer(YES);
  FBFMP4MuxerContext *ctx = [[FBFMP4MuxerContext alloc] initWithHEVC:NO];
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  id<FBControlCoreLogger> logger = [[FBControlCoreLoggerDouble alloc] init];
  NSError *error = nil;

  BOOL result = WriteH264FrameToFMP4Stream(sampleBuffer, ctx, consumer, logger, &error);
  XCTAssertTrue(result);
  XCTAssertNil(error);
  XCTAssertTrue(ctx.initWritten);

  NSData *output = consumer.data;
  XCTAssertGreaterThan(output.length, 16u);

  const uint8_t *bytes = output.bytes;

  // First box should be ftyp: [4-byte size]["ftyp"]
  XCTAssertEqual(bytes[4], 'f');
  XCTAssertEqual(bytes[5], 't');
  XCTAssertEqual(bytes[6], 'y');
  XCTAssertEqual(bytes[7], 'p');

  // Read ftyp box size and find moov after it
  uint32_t ftypSize = CFSwapInt32BigToHost(*(uint32_t *)bytes);
  XCTAssertGreaterThan(output.length, (NSUInteger)(ftypSize + 8));
  XCTAssertEqual(bytes[ftypSize + 4], 'm');
  XCTAssertEqual(bytes[ftypSize + 5], 'o');
  XCTAssertEqual(bytes[ftypSize + 6], 'o');
  XCTAssertEqual(bytes[ftypSize + 7], 'v');

  CFRelease(sampleBuffer);
}

- (void)testFMP4NonKeyframeBeforeFirstKeyframeDropped
{
  CMSampleBufferRef nonKeyframe = CreateH264SampleBuffer(NO);
  FBFMP4MuxerContext *ctx = [[FBFMP4MuxerContext alloc] initWithHEVC:NO];
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  id<FBControlCoreLogger> logger = [[FBControlCoreLoggerDouble alloc] init];
  NSError *error = nil;

  BOOL result = WriteH264FrameToFMP4Stream(nonKeyframe, ctx, consumer, logger, &error);
  XCTAssertTrue(result);
  XCTAssertNil(error);
  XCTAssertFalse(ctx.initWritten);
  XCTAssertEqual(consumer.data.length, 0u, @"No data should be written before first keyframe");

  CFRelease(nonKeyframe);
}

- (void)testFMP4FragmentContainsMoofAndMdat
{
  FBFMP4MuxerContext *ctx = [[FBFMP4MuxerContext alloc] initWithHEVC:NO];
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  id<FBControlCoreLogger> logger = [[FBControlCoreLoggerDouble alloc] init];

  CMSampleBufferRef keyframe = CreateH264SampleBuffer(YES);
  WriteH264FrameToFMP4Stream(keyframe, ctx, consumer, logger, nil);
  CFRelease(keyframe);

  NSData *output = consumer.data;
  NSData *moofType = [NSData dataWithBytes:"moof" length:4];
  NSData *mdatType = [NSData dataWithBytes:"mdat" length:4];

  NSRange moofRange = [output rangeOfData:moofType options:0 range:NSMakeRange(0, output.length)];
  XCTAssertNotEqual(moofRange.location, (NSUInteger)NSNotFound, @"Output should contain moof box");

  NSRange mdatRange = [output rangeOfData:mdatType options:0 range:NSMakeRange(0, output.length)];
  XCTAssertNotEqual(mdatRange.location, (NSUInteger)NSNotFound, @"Output should contain mdat box");

  XCTAssertTrue(moofRange.location < mdatRange.location);
  XCTAssertEqual(ctx.sequenceNumber, 1u);
}

- (void)testFMP4EmsgBoxStructure
{
  FBFMP4MuxerContext *ctx = [[FBFMP4MuxerContext alloc] initWithHEVC:NO];
  ctx.lastPts90k = 90000;
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;

  FBFMP4WriteEmsgBox(ctx, @"Chapter 1", consumer);

  NSData *output = consumer.data;
  XCTAssertGreaterThan(output.length, 12u);

  const uint8_t *bytes = output.bytes;

  // Box type should be "emsg"
  XCTAssertEqual(bytes[4], 'e');
  XCTAssertEqual(bytes[5], 'm');
  XCTAssertEqual(bytes[6], 's');
  XCTAssertEqual(bytes[7], 'g');

  uint32_t boxSize = CFSwapInt32BigToHost(*(uint32_t *)bytes);
  XCTAssertEqual(boxSize, (uint32_t)output.length);

  NSData *chapterText = [@"Chapter 1" dataUsingEncoding:NSUTF8StringEncoding];
  NSRange textRange = [output rangeOfData:chapterText options:0 range:NSMakeRange(0, output.length)];
  XCTAssertNotEqual(textRange.location, (NSUInteger)NSNotFound, @"Chapter text should be present in emsg box");
}

- (void)testFMP4NotReadyBufferReturnsError
{
  CMSampleBufferRef sampleBuffer = CreateNotReadySampleBuffer();
  FBFMP4MuxerContext *ctx = [[FBFMP4MuxerContext alloc] initWithHEVC:NO];
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  id<FBControlCoreLogger> logger = [[FBControlCoreLoggerDouble alloc] init];
  NSError *error = nil;

  BOOL result = WriteH264FrameToFMP4Stream(sampleBuffer, ctx, consumer, logger, &error);
  XCTAssertFalse(result);
  XCTAssertNotNil(error);
  XCTAssertTrue([error.localizedDescription containsString:@"Sample Buffer is not ready"]);
  XCTAssertEqual(consumer.data.length, 0u);

  CFRelease(sampleBuffer);
}

- (void)testFMP4NilContextReturnsError
{
  CMSampleBufferRef sampleBuffer = CreateH264SampleBuffer(YES);
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  id<FBControlCoreLogger> logger = [[FBControlCoreLoggerDouble alloc] init];
  NSError *error = nil;

  BOOL result = WriteH264FrameToFMP4Stream(sampleBuffer, nil, consumer, logger, &error);
  XCTAssertFalse(result);
  XCTAssertNotNil(error);

  CFRelease(sampleBuffer);
}

@end

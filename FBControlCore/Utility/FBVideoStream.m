/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBVideoStream.h"

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBDataConsumer.h"

static NSInteger const MaxAllowedUnprocessedDataCounts = 2;

BOOL checkConsumerBufferLimit(id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger) {
  if ([consumer conformsToProtocol:@protocol(FBDataConsumerAsync)]) {
    id<FBDataConsumerAsync> asyncConsumer = (id<FBDataConsumerAsync>)consumer;
    NSInteger framesInProcess = asyncConsumer.unprocessedDataCount;
    // drop frames if consumer is overflown
    if (framesInProcess > MaxAllowedUnprocessedDataCounts) {
      [logger logFormat:@"Consumer is overflown. Number of unsent frames: %@", @(framesInProcess)];
      return NO;
    }
  }
  return YES;
}

static NSData *AnnexBNALUStartCodeData(void)
{
  // https://www.programmersought.com/article/3901815022/
  // Annex-B is simpler as it is purely based on a start code to denote the start of the NALU.
  static NSData *data;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    const uint8_t headerCode[] = {0x00, 0x00, 0x00, 0x01};
    data = [NSData dataWithBytes:headerCode length:sizeof(headerCode)];
  });
  return data;
}

static const int AVCCHeaderLength = 4;

BOOL WriteFrameToAnnexBStream(CMSampleBufferRef sampleBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  if (!CMSampleBufferDataIsReady(sampleBuffer)) {
    return [[FBControlCoreError
      describeFormat:@"Sample Buffer is not ready"]
      failBool:error];
  }
  NSData *headerData = AnnexBNALUStartCodeData();
  NSMutableData *consumableData = [NSMutableData alloc];

  bool isKeyFrame = false;
  CFArrayRef attachments =
      CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
  if (CFArrayGetCount(attachments)) {
    CFDictionaryRef attachment = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    CFBooleanRef dependsOnOthers = (CFBooleanRef)CFDictionaryGetValue(
        attachment, kCMSampleAttachmentKey_DependsOnOthers);
    isKeyFrame = (dependsOnOthers == kCFBooleanFalse);
  }

  if (isKeyFrame) {
    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
    size_t spsSize, spsCount;
    const uint8_t *spsParameterSet;
    OSStatus status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
      format,
      0,
      &spsParameterSet,
      &spsSize,
      &spsCount,
      0
    );
    if (status != noErr) {
      return [[FBControlCoreError
        describeFormat:@"Failed to get SPS Params %d", status]
        failBool:error];
    }
    size_t ppsSize, ppsCount;
    const uint8_t *ppsParameterSet;
    status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
      format,
      1,
      &ppsParameterSet,
      &ppsSize,
      &ppsCount,
      0
    );
    if (status != noErr) {
      return [[FBControlCoreError
        describeFormat:@"Failed to get PPS Params %d", status]
        failBool:error];
    }
    NSData *spsData = [NSData dataWithBytes:spsParameterSet length:spsSize];
    NSData *ppsData = [NSData dataWithBytes:ppsParameterSet length:ppsSize];
    [consumableData appendData:headerData];
    [consumableData appendData:spsData];
    [consumableData appendData:headerData];
    [consumableData appendData:ppsData];
  }

  // Get the underlying data buffer.
  CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
  size_t dataLength;
  char *dataPointer;
  OSStatus status = CMBlockBufferGetDataPointer(
    dataBuffer,
    0,
    NULL,
    &dataLength,
    &dataPointer
  );
  if (status != noErr) {
    return [[FBControlCoreError
      describeFormat:@"Failed to get Data Pointer %d", status]
      failBool:error];
  }

  // Enumerate the data buffer
  size_t dataOffset = 0;
  while (dataOffset < dataLength - AVCCHeaderLength) {
    // Write start code to the elementary stream
    [consumableData appendData:headerData];

    // Get our current position in the buffer
    void *currentDataPointer = dataPointer + dataOffset;

    // Get the length of the NAL Unit, this is contained in the current offset.
    // This will tell us how many bytes to write in the current NAL unit, contained in the buffer.
    uint32_t nalLength = 0;
    memcpy(&nalLength, currentDataPointer, AVCCHeaderLength);
    // Convert the length value from Big-endian to Little-endian.
    nalLength = CFSwapInt32BigToHost(nalLength);

    // Write the NAL unit without the AVCC length header to the elementary stream
    void *nalUnitPointer = currentDataPointer + AVCCHeaderLength;
    if ([consumer conformsToProtocol:@protocol(FBDataConsumerSync)]) {
      NSData *nalUnitData = [NSData dataWithBytesNoCopy:nalUnitPointer length:nalLength freeWhenDone:NO];
      [consumableData appendData:nalUnitData];
    } else {
      NSData *nalUnitData = [NSData dataWithBytes:nalUnitPointer length:nalLength];
      [consumableData appendData:nalUnitData];
    }

    // Increment the offset for the next iteration.
    dataOffset += AVCCHeaderLength + nalLength;
  }
  [consumer consumeData:consumableData];
  return YES;
}

BOOL WriteJPEGDataToMJPEGStream(CMBlockBufferRef jpegDataBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  // Enumerate the data buffer
  size_t dataLength = CMBlockBufferGetDataLength(jpegDataBuffer);
  size_t offset = 0;
  while (offset < dataLength) {
    char *dataPointer;
    size_t lengthAtOffset;
    OSStatus status = CMBlockBufferGetDataPointer(
      jpegDataBuffer,
      offset,
      &lengthAtOffset,
      NULL,
      &dataPointer
    );
    if (status != noErr) {
      return [[FBControlCoreError
        describeFormat:@"Failed to get Data Pointer %d", status]
        failBool:error];
    }
    if ([consumer conformsToProtocol:@protocol(FBDataConsumerSync)]) {
      NSData *data = [NSData dataWithBytesNoCopy:dataPointer length:lengthAtOffset freeWhenDone:NO];
      [consumer consumeData:data];
    } else {
      NSData *data = [NSData dataWithBytes:dataPointer length:lengthAtOffset];
      [consumer consumeData:data];
    }

    // Increment the offset for the next iteration.
    offset += lengthAtOffset;
  }
  return YES;
}

BOOL WriteJPEGDataToMinicapStream(CMBlockBufferRef jpegDataBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  // Write the header length first
  size_t dataLength = CMBlockBufferGetDataLength(jpegDataBuffer);
  uint32 imageLength = OSSwapHostToLittleInt32(dataLength);
  NSData *lengthData = [[NSData alloc] initWithBytes:&imageLength length:sizeof(imageLength)];
  [consumer consumeData:lengthData];

  return WriteJPEGDataToMJPEGStream(jpegDataBuffer, consumer, logger, error);
}

// 1-byte alignment needed for the header to ensure correct sizing of the structure.
#pragma pack(push, 1)

// Should be 24 bytes long
// All integers are little-endian (https://github.com/openstf/minicap#usage)
struct MinicapHeader {
  unsigned char version;
  unsigned char headerSize;
  uint32 pid;
  uint32 displayWidth;
  uint32 displayHeight;
  uint32 virtualDisplayWidth;
  uint32 virtualDisplayHeight;
  unsigned char displayOrientation;
  unsigned char quirks;
};

#pragma pack(pop)

BOOL WriteMinicapHeaderToStream(uint32 width, uint32 height, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  struct MinicapHeader header = {
    .version = 1,
    .headerSize = sizeof(struct MinicapHeader),
    .pid = OSSwapHostToLittleInt32(NSProcessInfo.processInfo.processIdentifier),
    .displayWidth = OSSwapHostToLittleInt32(width),
    .displayHeight = OSSwapHostToLittleInt32(height),
    .virtualDisplayWidth = OSSwapHostToLittleInt32(width),
    .virtualDisplayHeight = OSSwapHostToLittleInt32(height),
    .displayOrientation = 0,
    .quirks = 0,
  };
  NSData *data = [[NSData alloc] initWithBytes:&header length:header.headerSize];
  [consumer consumeData:data];
  return YES;
}

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

static const int AVCCHeaderLength = 4;
static const uint8_t AnnexBStartCode[] = {0x00, 0x00, 0x00, 0x01};

BOOL WriteFrameToAnnexBStream(CMSampleBufferRef sampleBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  if (!CMSampleBufferDataIsReady(sampleBuffer)) {
    return [[FBControlCoreError
      describeFormat:@"Sample Buffer is not ready"]
      failBool:error];
  }

  bool isKeyFrame = false;
  CFArrayRef attachments =
      CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
  if (CFArrayGetCount(attachments)) {
    CFDictionaryRef attachment = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    isKeyFrame = !CFDictionaryContainsKey(attachment, kCMSampleAttachmentKey_NotSync);
  }

  // Convert AVCC length-prefixed NAL units to Annex-B start-code format.
  // Uses CMBlockBuffer APIs to safely handle non-contiguous or read-only backing memory.
  CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
  size_t dataLength = CMBlockBufferGetDataLength(dataBuffer);

  size_t offset = 0;
  while (offset < dataLength - AVCCHeaderLength) {
    uint8_t nalLengthBuf[AVCCHeaderLength];
    char *nalLengthPtr;
    OSStatus status = CMBlockBufferAccessDataBytes(dataBuffer, offset, AVCCHeaderLength, nalLengthBuf, &nalLengthPtr);
    if (status != noErr) {
      return [[FBControlCoreError
        describeFormat:@"Failed to access block buffer data at offset %zu: %d", offset, status]
        failBool:error];
    }
    uint32_t nalLength = 0;
    memcpy(&nalLength, nalLengthPtr, AVCCHeaderLength);
    nalLength = CFSwapInt32BigToHost(nalLength);
    status = CMBlockBufferReplaceDataBytes(AnnexBStartCode, dataBuffer, offset, AVCCHeaderLength);
    if (status != noErr) {
      return [[FBControlCoreError
        describeFormat:@"Failed to replace block buffer data at offset %zu: %d", offset, status]
        failBool:error];
    }
    offset += AVCCHeaderLength + nalLength;
  }

  if (isKeyFrame) {
    // Keyframes: send parameter sets (SPS, PPS) first, then the converted block buffer.
    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
    size_t parameterSetCount;
    OSStatus status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
      format, 0, NULL, NULL, &parameterSetCount, NULL
    );
    if (status != noErr) {
      return [[FBControlCoreError
        describeFormat:@"Failed to get H264 parameter set count %d", status]
        failBool:error];
    }
    for (size_t i = 0; i < parameterSetCount; i++) {
      size_t paramSize;
      const uint8_t *parameterSet;
      status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        format, i, &parameterSet, &paramSize, NULL, NULL
      );
      if (status != noErr) {
        return [[FBControlCoreError
          describeFormat:@"Failed to get H264 parameter set at index %zu: %d", i, status]
          failBool:error];
      }
      uint8_t paramHeader[AVCCHeaderLength + paramSize];
      memcpy(paramHeader, AnnexBStartCode, AVCCHeaderLength);
      memcpy(paramHeader + AVCCHeaderLength, parameterSet, paramSize);
      [consumer consumeData:[NSData dataWithBytes:paramHeader length:sizeof(paramHeader)]];
    }
  }

  // Send the converted block buffer data, iterating contiguous segments.
  BOOL isSyncConsumer = [consumer conformsToProtocol:@protocol(FBDataConsumerSync)];
  size_t sendOffset = 0;
  while (sendOffset < dataLength) {
    char *dataPointer;
    size_t lengthAtOffset;
    OSStatus status = CMBlockBufferGetDataPointer(dataBuffer, sendOffset, &lengthAtOffset, NULL, &dataPointer);
    if (status != noErr) {
      return [[FBControlCoreError
        describeFormat:@"Failed to get Data Pointer %d", status]
        failBool:error];
    }
    if (isSyncConsumer) {
      [consumer consumeData:[NSData dataWithBytesNoCopy:dataPointer length:lengthAtOffset freeWhenDone:NO]];
    } else {
      [consumer consumeData:[NSData dataWithBytes:dataPointer length:lengthAtOffset]];
    }
    sendOffset += lengthAtOffset;
  }
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

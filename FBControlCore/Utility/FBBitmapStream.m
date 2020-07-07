/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBBitmapStream.h"

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBDataConsumer.h"

static NSData *AnnexBNALUStartCodeData()
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
  NSArray<id> *attachmentsArray = (NSArray<id> *) CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
  BOOL hasKeyframe = attachmentsArray[0][(NSString *) kCMSampleAttachmentKey_NotSync] != nil;
  if (hasKeyframe) {
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
    [consumer consumeData:headerData];
    [consumer consumeData:spsData];
    [consumer consumeData:headerData];
    [consumer consumeData:ppsData];
    [logger logFormat:@"Pushing Keyframe"];
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
    [consumer consumeData:headerData];

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
    NSData *nalUnitData = [NSData dataWithBytes:nalUnitPointer length:nalLength];
    [consumer consumeData:nalUnitData];

    // Increment the offset for the next iteration.
    dataOffset += AVCCHeaderLength + nalLength;
  }
  return YES;
}


FBiOSTargetFutureType const FBiOSTargetFutureTypeVideoStreaming = @"VideoStreaming";

@implementation FBBitmapStreamAttributes

- (instancetype)initWithAttributes:(NSDictionary<NSString *, id> *)attributes
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _attributes = attributes;
  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [FBCollectionInformation oneLineDescriptionFromDictionary:self.attributes];
}

#pragma mark FBJSONSerializable

- (id)jsonSerializableRepresentation
{
  return self.attributes;
}

@end

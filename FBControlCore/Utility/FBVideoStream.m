/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBVideoStream.h"

#import <os/lock.h>

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

/**
 Write the contents of a CMBlockBuffer to a data consumer, iterating contiguous segments.
 Sync consumers receive zero-copy NSData backed by the buffer's memory; async consumers receive a copy.
 */
static BOOL WriteBlockBufferToConsumer(CMBlockBufferRef blockBuffer, id<FBDataConsumer> consumer, NSError **error)
{
  size_t dataLength = CMBlockBufferGetDataLength(blockBuffer);
  BOOL isSyncConsumer = [consumer conformsToProtocol:@protocol(FBDataConsumerSync)];
  size_t offset = 0;
  while (offset < dataLength) {
    char *dataPointer;
    size_t lengthAtOffset;
    OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, offset, &lengthAtOffset, NULL, &dataPointer);
    if (status != noErr) {
      return [[FBControlCoreError
        describeFormat:@"Failed to get Data Pointer at offset %zu: %d", offset, status]
        failBool:error];
    }
    if (isSyncConsumer) {
      [consumer consumeData:[NSData dataWithBytesNoCopy:dataPointer length:lengthAtOffset freeWhenDone:NO]];
    } else {
      [consumer consumeData:[NSData dataWithBytes:dataPointer length:lengthAtOffset]];
    }
    offset += lengthAtOffset;
  }
  return YES;
}

static BOOL ConvertAVCCToAnnexBInPlace(CMSampleBufferRef sampleBuffer, NSError **error)
{
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
  return YES;
}

// H264 and HEVC parameter set getters have identical signatures.
typedef OSStatus (*FBVideoParameterSetGetter)(CMFormatDescriptionRef, size_t, const uint8_t * _Nullable *, size_t *, size_t *, int *);

static BOOL WriteCodecFrameToAnnexBStream(CMSampleBufferRef sampleBuffer, FBVideoParameterSetGetter paramSetGetter, NSString *codecName, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
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

  // Convert AVCC length-prefixed NAL units to Annex-B start-code format in place.
  if (!ConvertAVCCToAnnexBInPlace(sampleBuffer, error)) {
    return NO;
  }

  // Get the block buffer for parameter sets and consumer write.
  CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);

  if (isKeyFrame) {
    // Keyframes: send parameter sets (SPS, PPS / VPS, SPS, PPS) first, then the converted block buffer.
    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
    size_t parameterSetCount;
    OSStatus status = paramSetGetter(format, 0, NULL, NULL, &parameterSetCount, NULL);
    if (status != noErr) {
      return [[FBControlCoreError
        describeFormat:@"Failed to get %@ parameter set count %d", codecName, status]
        failBool:error];
    }
    for (size_t i = 0; i < parameterSetCount; i++) {
      size_t paramSize;
      const uint8_t *parameterSet;
      status = paramSetGetter(format, i, &parameterSet, &paramSize, NULL, NULL);
      if (status != noErr) {
        return [[FBControlCoreError
          describeFormat:@"Failed to get %@ parameter set at index %zu: %d", codecName, i, status]
          failBool:error];
      }
      uint8_t paramHeader[AVCCHeaderLength + paramSize];
      memcpy(paramHeader, AnnexBStartCode, AVCCHeaderLength);
      memcpy(paramHeader + AVCCHeaderLength, parameterSet, paramSize);
      [consumer consumeData:[NSData dataWithBytes:paramHeader length:sizeof(paramHeader)]];
    }
  }

  // Send the converted block buffer data.
  return WriteBlockBufferToConsumer(dataBuffer, consumer, error);
}

BOOL WriteFrameToAnnexBStream(CMSampleBufferRef sampleBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  return WriteCodecFrameToAnnexBStream(sampleBuffer, CMVideoFormatDescriptionGetH264ParameterSetAtIndex, @"H264", consumer, logger, error);
}

BOOL WriteHEVCFrameToAnnexBStream(CMSampleBufferRef sampleBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  return WriteCodecFrameToAnnexBStream(sampleBuffer, CMVideoFormatDescriptionGetHEVCParameterSetAtIndex, @"HEVC", consumer, logger, error);
}

#pragma mark - MPEG-TS Writer

static const int TSPacketSize = 188;
static const uint8_t TSSyncByte = 0x47;
static const uint16_t PATPID = 0x0000;
static const uint16_t PMTPID = 0x0100;
static const uint16_t VideoPID = 0x0101;
const uint16_t FBMPEGTSMetadataPID = 0x0102;
static const uint8_t HEVCStreamType = 0x24;
static const uint8_t H264StreamType = 0x1B;
static const uint8_t TimedMetadataStreamType = 0x15; // PES private data (ID3)

uint32_t FBMPEGTS_CRC32(const uint8_t *data, size_t length)
{
  static uint32_t table[256];
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    for (uint32_t i = 0; i < 256; i++) {
      uint32_t crc = i << 24;
      for (int j = 0; j < 8; j++) {
        if (crc & 0x80000000) {
          crc = (crc << 1) ^ 0x04C11DB7;
        } else {
          crc <<= 1;
        }
      }
      table[i] = crc;
    }
  });
  uint32_t crc = 0xFFFFFFFF;
  for (size_t i = 0; i < length; i++) {
    crc = (crc << 8) ^ table[((crc >> 24) ^ data[i]) & 0xFF];
  }
  return crc;
}

NSData *FBMPEGTSCreatePATPacket(uint8_t *continuityCounter)
{
  uint8_t packet[TSPacketSize];
  memset(packet, 0xFF, TSPacketSize);

  // TS header
  packet[0] = TSSyncByte;
  packet[1] = 0x40 | ((PATPID >> 8) & 0x1F); // payload_unit_start=1
  packet[2] = PATPID & 0xFF;
  packet[3] = 0x10 | ((*continuityCounter) & 0x0F); // no adaptation, payload only
  (*continuityCounter)++;

  // Pointer field
  packet[4] = 0x00;

  // PAT section
  uint8_t *section = &packet[5];
  section[0] = 0x00; // table_id = PAT
  // section_length will be filled after
  section[3] = 0x00; section[4] = 0x01; // transport_stream_id = 1
  section[5] = 0xC1; // version=0, current_next=1
  section[6] = 0x00; // section_number
  section[7] = 0x00; // last_section_number
  // Program 1 -> PMT PID
  section[8] = 0x00; section[9] = 0x01; // program_number = 1
  section[10] = 0xE0 | ((PMTPID >> 8) & 0x1F);
  section[11] = PMTPID & 0xFF;
  // section_length = 13 (5 bytes after length field + 4 program + 4 CRC)
  uint16_t sectionLength = 9 + 4; // 9 bytes data + 4 CRC
  section[1] = 0xB0 | ((sectionLength >> 8) & 0x0F);
  section[2] = sectionLength & 0xFF;

  uint32_t crc = FBMPEGTS_CRC32(section, 12);
  section[12] = (crc >> 24) & 0xFF;
  section[13] = (crc >> 16) & 0xFF;
  section[14] = (crc >> 8) & 0xFF;
  section[15] = crc & 0xFF;

  return [NSData dataWithBytes:packet length:TSPacketSize];
}

NSData *FBMPEGTSCreatePMTPacket(uint8_t *continuityCounter, uint8_t streamType)
{
  uint8_t packet[TSPacketSize];
  memset(packet, 0xFF, TSPacketSize);

  // TS header
  packet[0] = TSSyncByte;
  packet[1] = 0x40 | ((PMTPID >> 8) & 0x1F); // payload_unit_start=1
  packet[2] = PMTPID & 0xFF;
  packet[3] = 0x10 | ((*continuityCounter) & 0x0F);
  (*continuityCounter)++;

  // Pointer field
  packet[4] = 0x00;

  // PMT section
  uint8_t *section = &packet[5];
  section[0] = 0x02; // table_id = PMT
  // section_length filled after
  section[3] = 0x00; section[4] = 0x01; // program_number = 1
  section[5] = 0xC1; // version=0, current_next=1
  section[6] = 0x00; // section_number
  section[7] = 0x00; // last_section_number
  // PCR PID = VideoPID
  section[8] = 0xE0 | ((VideoPID >> 8) & 0x1F);
  section[9] = VideoPID & 0xFF;
  // program_info_length = 0
  section[10] = 0xF0;
  section[11] = 0x00;
  // Stream entry
  section[12] = streamType;
  section[13] = 0xE0 | ((VideoPID >> 8) & 0x1F);
  section[14] = VideoPID & 0xFF;
  // ES_info_length = 0
  section[15] = 0xF0;
  section[16] = 0x00;

  uint16_t sectionLength = 13 + 4; // 13 bytes data + 4 CRC
  section[1] = 0xB0 | ((sectionLength >> 8) & 0x0F);
  section[2] = sectionLength & 0xFF;

  uint32_t crc = FBMPEGTS_CRC32(section, 17);
  section[17] = (crc >> 24) & 0xFF;
  section[18] = (crc >> 16) & 0xFF;
  section[19] = (crc >> 8) & 0xFF;
  section[20] = crc & 0xFF;

  return [NSData dataWithBytes:packet length:TSPacketSize];
}

// Forward declaration of metadata state used by FBMPEGTSPacketizePES
static BOOL metadataStreamEnabled = NO;

NSData *FBMPEGTSPacketizePES(NSData *pesData, BOOL isKeyFrame, uint8_t streamType,
                                   uint64_t pts90k,
                                   uint8_t *videoContinuityCounter,
                                   uint8_t *patContinuityCounter, uint8_t *pmtContinuityCounter)
{
  // First packet carries at most 176 bytes (PCR adaptation field uses 8 bytes),
  // remaining packets carry 184 bytes each.
  size_t firstPayload = pesData.length < 176 ? pesData.length : 176;
  size_t remainingBytes = pesData.length - firstPayload;
  size_t numVideoPackets = 1 + (remainingBytes + 183) / 184;
  size_t totalPackets = (isKeyFrame ? 2 : 0) + numVideoPackets;
  NSMutableData *output = [[NSMutableData alloc] initWithCapacity:totalPackets * TSPacketSize];

  // Emit PAT + PMT on keyframes for mid-stream join support
  if (isKeyFrame) {
    [output appendData:FBMPEGTSCreatePATPacket(patContinuityCounter)];
    [output appendData:FBMPEGTSCreatePMTPacketWithMetadata(pmtContinuityCounter, streamType, metadataStreamEnabled)];
  }

  const uint8_t *pesBytes = (const uint8_t *)pesData.bytes;
  size_t pesLength = pesData.length;
  size_t pesOffset = 0;
  BOOL first = YES;

  while (pesOffset < pesLength) {
    uint8_t packet[TSPacketSize];
    memset(packet, 0xFF, TSPacketSize);

    // TS header (4 bytes)
    packet[0] = TSSyncByte;
    packet[1] = (first ? 0x40 : 0x00) | ((VideoPID >> 8) & 0x1F);
    packet[2] = VideoPID & 0xFF;

    size_t headerSize = 4;
    size_t remaining = pesLength - pesOffset;

    if (first) {
      // First packet of each access unit: include adaptation field with PCR
      packet[3] = 0x30 | ((*videoContinuityCounter) & 0x0F); // adaptation + payload
      packet[4] = 0x07; // adaptation_field_length = 7
      packet[5] = 0x10; // flags: PCR present
      // PCR encoding: 33-bit base (90kHz) + 6 reserved bits (all 1) + 9-bit extension (0)
      uint64_t pcrBase = pts90k;
      packet[6]  = (uint8_t)(pcrBase >> 25);
      packet[7]  = (uint8_t)(pcrBase >> 17);
      packet[8]  = (uint8_t)(pcrBase >> 9);
      packet[9]  = (uint8_t)(pcrBase >> 1);
      packet[10] = (uint8_t)(((pcrBase & 1) << 7) | 0x7E); // base LSB + 6 reserved bits
      packet[11] = 0x00; // extension = 0
      headerSize = 12;

      size_t payloadCapacity = TSPacketSize - headerSize; // 176
      if (remaining < payloadCapacity) {
        // Extend adaptation field with stuffing bytes
        size_t stuffingNeeded = payloadCapacity - remaining;
        packet[4] = (uint8_t)(0x07 + stuffingNeeded); // extend adaptation_field_length
        memset(&packet[12], 0xFF, stuffingNeeded);
        headerSize = 12 + stuffingNeeded;
      }
    } else {
      size_t payloadCapacity = TSPacketSize - headerSize; // 184
      if (remaining < payloadCapacity) {
        // Need adaptation field for stuffing
        size_t stuffingBytes = payloadCapacity - remaining;
        if (stuffingBytes == 1) {
          // adaptation_field_length = 0, just the length byte
          packet[3] = 0x30 | ((*videoContinuityCounter) & 0x0F);
          packet[4] = 0x00; // adaptation_field_length = 0
          headerSize = 5;
        } else {
          packet[3] = 0x30 | ((*videoContinuityCounter) & 0x0F);
          packet[4] = (uint8_t)(stuffingBytes - 1); // adaptation_field_length
          if (stuffingBytes > 1) {
            packet[5] = 0x00; // flags
            memset(&packet[6], 0xFF, stuffingBytes - 2);
          }
          headerSize = 4 + stuffingBytes;
        }
      } else {
        packet[3] = 0x10 | ((*videoContinuityCounter) & 0x0F);
      }
    }

    (*videoContinuityCounter)++;
    size_t payloadSize = TSPacketSize - headerSize;
    if (payloadSize > remaining) {
      payloadSize = remaining;
    }
    memcpy(&packet[headerSize], pesBytes + pesOffset, payloadSize);
    pesOffset += payloadSize;
    first = NO;

    [output appendBytes:packet length:TSPacketSize];
  }

  return output;
}

NSData *FBMPEGTSCreatePMTPacketWithMetadata(uint8_t *continuityCounter, uint8_t streamType, BOOL includeMetadataStream)
{
  if (!includeMetadataStream) {
    return FBMPEGTSCreatePMTPacket(continuityCounter, streamType);
  }

  uint8_t packet[TSPacketSize];
  memset(packet, 0xFF, TSPacketSize);

  // TS header
  packet[0] = TSSyncByte;
  packet[1] = 0x40 | ((PMTPID >> 8) & 0x1F);
  packet[2] = PMTPID & 0xFF;
  packet[3] = 0x10 | ((*continuityCounter) & 0x0F);
  (*continuityCounter)++;

  // Pointer field
  packet[4] = 0x00;

  // PMT section
  uint8_t *section = &packet[5];
  section[0] = 0x02; // table_id = PMT
  section[3] = 0x00; section[4] = 0x01; // program_number = 1
  section[5] = 0xC1; // version=0, current_next=1
  section[6] = 0x00; // section_number
  section[7] = 0x00; // last_section_number
  // PCR PID = VideoPID
  section[8] = 0xE0 | ((VideoPID >> 8) & 0x1F);
  section[9] = VideoPID & 0xFF;
  // program_info_length = 0
  section[10] = 0xF0;
  section[11] = 0x00;
  // Video stream entry
  section[12] = streamType;
  section[13] = 0xE0 | ((VideoPID >> 8) & 0x1F);
  section[14] = VideoPID & 0xFF;
  section[15] = 0xF0;
  section[16] = 0x00; // ES_info_length = 0
  // Metadata stream entry
  section[17] = TimedMetadataStreamType;
  section[18] = 0xE0 | ((FBMPEGTSMetadataPID >> 8) & 0x1F);
  section[19] = FBMPEGTSMetadataPID & 0xFF;
  section[20] = 0xF0;
  section[21] = 0x00; // ES_info_length = 0

  // section_length = 9 (header after length) + 5 (video entry) + 5 (metadata entry) + 4 (CRC) = 23
  // But PMT section data before CRC is: bytes [3..21] = 19 bytes. section_length covers from byte [3] to end including CRC.
  // section_length = (21 - 3 + 1) + 4 = 23
  uint16_t sectionLength = 18 + 4; // 18 bytes data after section_length field + 4 CRC
  section[1] = 0xB0 | ((sectionLength >> 8) & 0x0F);
  section[2] = sectionLength & 0xFF;

  uint32_t crc = FBMPEGTS_CRC32(section, 22);
  section[22] = (crc >> 24) & 0xFF;
  section[23] = (crc >> 16) & 0xFF;
  section[24] = (crc >> 8) & 0xFF;
  section[25] = crc & 0xFF;

  return [NSData dataWithBytes:packet length:TSPacketSize];
}

NSData *FBMPEGTSCreateTimedMetadataPackets(NSString *text, uint64_t pts90k, uint8_t *metadataContinuityCounter)
{
  NSData *textData = [text dataUsingEncoding:NSUTF8StringEncoding];

  // Build ID3v2.4 tag: header (10 bytes) + TXXX frame
  // TXXX frame: header (10 bytes) + encoding (1) + null description (1) + text
  size_t txxxPayloadLen = 1 + 1 + textData.length; // encoding + null desc + text
  size_t id3PayloadLen = 10 + txxxPayloadLen;       // TXXX frame header + payload
  size_t id3TotalLen = 10 + id3PayloadLen;          // ID3 header + payload

  NSMutableData *id3Tag = [[NSMutableData alloc] initWithCapacity:id3TotalLen];

  // ID3v2 header
  uint8_t id3Header[10] = {
    'I', 'D', '3',
    0x04, 0x00,  // version 2.4
    0x00,        // flags
    (uint8_t)((id3PayloadLen >> 21) & 0x7F),
    (uint8_t)((id3PayloadLen >> 14) & 0x7F),
    (uint8_t)((id3PayloadLen >> 7)  & 0x7F),
    (uint8_t)(id3PayloadLen & 0x7F),
  };
  [id3Tag appendBytes:id3Header length:10];

  // TXXX frame header
  uint8_t txxxHeader[10] = {
    'T', 'X', 'X', 'X',
    (uint8_t)((txxxPayloadLen >> 24) & 0xFF),
    (uint8_t)((txxxPayloadLen >> 16) & 0xFF),
    (uint8_t)((txxxPayloadLen >> 8)  & 0xFF),
    (uint8_t)(txxxPayloadLen & 0xFF),
    0x00, 0x00,  // flags
  };
  [id3Tag appendBytes:txxxHeader length:10];

  // TXXX payload: UTF-8 encoding (0x03), empty description (\0), then text
  uint8_t txxxPrefix[2] = {0x03, 0x00}; // encoding=UTF-8, null-terminated empty description
  [id3Tag appendBytes:txxxPrefix length:2];
  [id3Tag appendData:textData];

  // Wrap in PES packet (stream_id = 0xBD = private_stream_1)
  size_t pesHeaderLen = 14; // 9 base + 5 PTS
  size_t pesTotalLen = pesHeaderLen + id3Tag.length;
  uint16_t pesPacketLength = (pesTotalLen - 6 <= 0xFFFF) ? (uint16_t)(pesTotalLen - 6) : 0;

  NSMutableData *pesPacket = [[NSMutableData alloc] initWithCapacity:pesTotalLen];
  uint8_t pesHeader[14];
  pesHeader[0] = 0x00; pesHeader[1] = 0x00; pesHeader[2] = 0x01;
  pesHeader[3] = 0xBD; // private_stream_1
  pesHeader[4] = (pesPacketLength >> 8) & 0xFF;
  pesHeader[5] = pesPacketLength & 0xFF;
  pesHeader[6] = 0x80; // marker bits
  pesHeader[7] = 0x80; // PTS present, no DTS
  pesHeader[8] = 0x05; // PES header data length (5 bytes for PTS)
  // PTS encoding (indicator nibble 0x2 when PTS only)
  pesHeader[9]  = 0x21 | (uint8_t)(((pts90k >> 29) & 0x0E));
  pesHeader[10] = (uint8_t)((pts90k >> 22) & 0xFF);
  pesHeader[11] = (uint8_t)(((pts90k >> 14) & 0xFE) | 0x01);
  pesHeader[12] = (uint8_t)((pts90k >> 7) & 0xFF);
  pesHeader[13] = (uint8_t)(((pts90k << 1) & 0xFE) | 0x01);
  [pesPacket appendBytes:pesHeader length:pesHeaderLen];
  [pesPacket appendData:id3Tag];

  // Packetize into TS packets on MetadataPID
  const uint8_t *pesBytes = (const uint8_t *)pesPacket.bytes;
  size_t pesLength = pesPacket.length;
  size_t numPackets = (pesLength + 183) / 184;
  NSMutableData *output = [[NSMutableData alloc] initWithCapacity:numPackets * TSPacketSize];

  size_t pesOffset = 0;
  BOOL first = YES;

  while (pesOffset < pesLength) {
    uint8_t packet[TSPacketSize];
    memset(packet, 0xFF, TSPacketSize);
    packet[0] = TSSyncByte;
    packet[1] = (first ? 0x40 : 0x00) | ((FBMPEGTSMetadataPID >> 8) & 0x1F);
    packet[2] = FBMPEGTSMetadataPID & 0xFF;

    size_t headerSize = 4;
    size_t remaining = pesLength - pesOffset;
    size_t payloadCapacity = TSPacketSize - headerSize; // 184

    if (remaining < payloadCapacity) {
      size_t stuffingBytes = payloadCapacity - remaining;
      if (stuffingBytes == 1) {
        packet[3] = 0x30 | ((*metadataContinuityCounter) & 0x0F);
        packet[4] = 0x00;
        headerSize = 5;
      } else {
        packet[3] = 0x30 | ((*metadataContinuityCounter) & 0x0F);
        packet[4] = (uint8_t)(stuffingBytes - 1);
        if (stuffingBytes > 1) {
          packet[5] = 0x00;
          if (stuffingBytes > 2) {
            memset(&packet[6], 0xFF, stuffingBytes - 2);
          }
        }
        headerSize = 4 + stuffingBytes;
      }
    } else {
      packet[3] = 0x10 | ((*metadataContinuityCounter) & 0x0F);
    }

    (*metadataContinuityCounter)++;
    size_t payloadSize = TSPacketSize - headerSize;
    if (payloadSize > remaining) {
      payloadSize = remaining;
    }
    memcpy(&packet[headerSize], pesBytes + pesOffset, payloadSize);
    pesOffset += payloadSize;
    first = NO;

    [output appendBytes:packet length:TSPacketSize];
  }

  return output;
}

#pragma mark - MPEG-TS Metadata State

static os_unfair_lock metadataLock = OS_UNFAIR_LOCK_INIT;
static uint8_t metadataContinuityCounter = 0;
static uint64_t lastPts90k = 0;

void FBMPEGTSEnableMetadataStream(void)
{
  os_unfair_lock_lock(&metadataLock);
  metadataStreamEnabled = YES;
  os_unfair_lock_unlock(&metadataLock);
}

void FBMPEGTSWriteTimedMetadata(NSString *text, id<FBDataConsumer> consumer)
{
  os_unfair_lock_lock(&metadataLock);
  if (!metadataStreamEnabled) {
    os_unfair_lock_unlock(&metadataLock);
    return;
  }
  uint64_t pts = lastPts90k;
  NSData *packets = FBMPEGTSCreateTimedMetadataPackets(text, pts, &metadataContinuityCounter);
  os_unfair_lock_unlock(&metadataLock);

  [consumer consumeData:packets];
}

static BOOL WriteCodecFrameToMPEGTSStream(CMSampleBufferRef sampleBuffer, FBVideoParameterSetGetter paramSetGetter, NSString *codecName, uint8_t mpegtsStreamType, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  if (!CMSampleBufferDataIsReady(sampleBuffer)) {
    return [[FBControlCoreError
      describeFormat:@"Sample Buffer is not ready"]
      failBool:error];
  }

  // Continuity counters persist across calls via static variables
  static uint8_t videoContinuityCounter = 0;
  static uint8_t patContinuityCounter = 0;
  static uint8_t pmtContinuityCounter = 0;

  bool isKeyFrame = false;
  CFArrayRef attachments =
      CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
  if (CFArrayGetCount(attachments)) {
    CFDictionaryRef attachment = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    isKeyFrame = !CFDictionaryContainsKey(attachment, kCMSampleAttachmentKey_NotSync);
  }

  // Convert AVCC to Annex-B in place before computing sizes.
  // AVCC headers and Annex-B start codes are both 4 bytes so sizes are unchanged.
  if (!ConvertAVCCToAnnexBInPlace(sampleBuffer, error)) {
    return NO;
  }

  CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
  size_t dataLength = CMBlockBufferGetDataLength(dataBuffer);

  // Compute parameter set sizes upfront (if keyframe) so we can allocate a single buffer.
  size_t parameterSetSize = 0;
  CMFormatDescriptionRef format = NULL;
  size_t parameterSetCount = 0;
  if (isKeyFrame) {
    format = CMSampleBufferGetFormatDescription(sampleBuffer);
    OSStatus status = paramSetGetter(format, 0, NULL, NULL, &parameterSetCount, NULL);
    if (status != noErr) {
      return [[FBControlCoreError
        describeFormat:@"Failed to get %@ parameter set count %d", codecName, status]
        failBool:error];
    }
    for (size_t i = 0; i < parameterSetCount; i++) {
      size_t paramSize;
      status = paramSetGetter(format, i, NULL, &paramSize, NULL, NULL);
      if (status != noErr) {
        return [[FBControlCoreError
          describeFormat:@"Failed to get %@ parameter set at index %zu: %d", codecName, i, status]
          failBool:error];
      }
      parameterSetSize += AVCCHeaderLength + paramSize;
    }
  }

  // Build PES packet in a single allocation: 19-byte header + parameter sets + NAL data.
  // PES header: start code (3) + stream_id (1) + length (2) + flags (2) + header data length (1) = 9
  // With PTS + DTS: add 10 bytes = 19 bytes header
  size_t pesHeaderLength = 19;
  size_t pesPayloadLength = parameterSetSize + dataLength;
  size_t pesTotalLength = pesHeaderLength + pesPayloadLength;
  // PES packet_length field: 0 means unbounded for video, but we'll set it if it fits
  uint16_t pesPacketLength = 0;
  if (pesTotalLength - 6 <= 0xFFFF) {
    pesPacketLength = (uint16_t)(pesTotalLength - 6);
  }

  CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
  uint64_t pts90k = (uint64_t)(CMTimeGetSeconds(pts) * 90000.0);

  // Update the shared last PTS for timed metadata injection
  os_unfair_lock_lock(&metadataLock);
  lastPts90k = pts90k;
  os_unfair_lock_unlock(&metadataLock);

  NSMutableData *pesPacket = [[NSMutableData alloc] initWithCapacity:pesTotalLength];

  // PES start code prefix + stream_id (0xE0 = video)
  uint8_t pesHeader[19];
  pesHeader[0] = 0x00;
  pesHeader[1] = 0x00;
  pesHeader[2] = 0x01;
  pesHeader[3] = 0xE0; // stream_id: video
  pesHeader[4] = (pesPacketLength >> 8) & 0xFF;
  pesHeader[5] = pesPacketLength & 0xFF;
  pesHeader[6] = 0x80; // marker bits
  pesHeader[7] = 0xC0; // PTS + DTS present
  pesHeader[8] = 0x0A; // PES header data length (10 bytes for PTS + DTS)

  // PTS encoding (33-bit value in 5 bytes, indicator nibble 0x3 when DTS present)
  pesHeader[9]  = 0x31 | (uint8_t)(((pts90k >> 29) & 0x0E));
  pesHeader[10] = (uint8_t)((pts90k >> 22) & 0xFF);
  pesHeader[11] = (uint8_t)(((pts90k >> 14) & 0xFE) | 0x01);
  pesHeader[12] = (uint8_t)((pts90k >> 7) & 0xFF);
  pesHeader[13] = (uint8_t)(((pts90k << 1) & 0xFE) | 0x01);

  // DTS encoding (33-bit value in 5 bytes, indicator nibble 0x1)
  // DTS == PTS since AllowFrameReordering is NO (decode order = presentation order)
  pesHeader[14] = 0x11 | (uint8_t)(((pts90k >> 29) & 0x0E));
  pesHeader[15] = (uint8_t)((pts90k >> 22) & 0xFF);
  pesHeader[16] = (uint8_t)(((pts90k >> 14) & 0xFE) | 0x01);
  pesHeader[17] = (uint8_t)((pts90k >> 7) & 0xFF);
  pesHeader[18] = (uint8_t)(((pts90k << 1) & 0xFE) | 0x01);

  [pesPacket appendBytes:pesHeader length:pesHeaderLength];

  // Append parameter sets for keyframes (start code + set bytes for each)
  if (isKeyFrame) {
    for (size_t i = 0; i < parameterSetCount; i++) {
      size_t paramSize;
      const uint8_t *parameterSet;
      paramSetGetter(format, i, &parameterSet, &paramSize, NULL, NULL);
      [pesPacket appendBytes:AnnexBStartCode length:AVCCHeaderLength];
      [pesPacket appendBytes:parameterSet length:paramSize];
    }
  }

  // Copy NAL data directly from CMBlockBuffer into pesPacket (handles non-contiguous buffers)
  [pesPacket increaseLengthBy:dataLength];
  uint8_t *nalDest = (uint8_t *)pesPacket.mutableBytes + pesHeaderLength + parameterSetSize;
  OSStatus copyStatus = CMBlockBufferCopyDataBytes(dataBuffer, 0, dataLength, nalDest);
  if (copyStatus != noErr) {
    return [[FBControlCoreError
      describeFormat:@"Failed to copy block buffer data: %d", copyStatus]
      failBool:error];
  }

  // Packetize into MPEG-TS and write to consumer
  NSData *tsData = FBMPEGTSPacketizePES(pesPacket, isKeyFrame, mpegtsStreamType,
                                         pts90k,
                                         &videoContinuityCounter,
                                         &patContinuityCounter, &pmtContinuityCounter);
  [consumer consumeData:tsData];

  return YES;
}

BOOL WriteHEVCFrameToMPEGTSStream(CMSampleBufferRef sampleBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  return WriteCodecFrameToMPEGTSStream(sampleBuffer, CMVideoFormatDescriptionGetHEVCParameterSetAtIndex, @"HEVC", HEVCStreamType, consumer, logger, error);
}

BOOL WriteH264FrameToMPEGTSStream(CMSampleBufferRef sampleBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  return WriteCodecFrameToMPEGTSStream(sampleBuffer, CMVideoFormatDescriptionGetH264ParameterSetAtIndex, @"H264", H264StreamType, consumer, logger, error);
}

BOOL WriteJPEGDataToMJPEGStream(CMBlockBufferRef jpegDataBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  return WriteBlockBufferToConsumer(jpegDataBuffer, consumer, error);
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

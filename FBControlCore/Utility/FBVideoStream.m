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

BOOL checkConsumerBufferLimit(id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger)
{
  if ([consumer conformsToProtocol:@protocol(FBDataConsumerAsync)]) {
    id<FBDataConsumerAsync> asyncConsumer = (id<FBDataConsumerAsync>)consumer;
    NSInteger framesInProcess = asyncConsumer.unprocessedDataCount;
    // drop frames if consumer is overflown
    if (framesInProcess > MaxAllowedUnprocessedDataCounts) {
      [logger log:[NSString stringWithFormat:@"Consumer is overflown. Number of unsent frames: %@", @(framesInProcess)]];
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
               describe:[NSString stringWithFormat:@"Failed to get Data Pointer at offset %zu: %d", offset, status]]
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
               describe:[NSString stringWithFormat:@"Failed to access block buffer data at offset %zu: %d", offset, status]]
              failBool:error];
    }
    uint32_t nalLength = 0;
    memcpy(&nalLength, nalLengthPtr, AVCCHeaderLength);
    nalLength = CFSwapInt32BigToHost(nalLength);
    status = CMBlockBufferReplaceDataBytes(AnnexBStartCode, dataBuffer, offset, AVCCHeaderLength);
    if (status != noErr) {
      return [[FBControlCoreError
               describe:[NSString stringWithFormat:@"Failed to replace block buffer data at offset %zu: %d", offset, status]]
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
             describe:@"Sample Buffer is not ready"]
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
               describe:[NSString stringWithFormat:@"Failed to get %@ parameter set count %d", codecName, status]]
              failBool:error];
    }
    for (size_t i = 0; i < parameterSetCount; i++) {
      size_t paramSize;
      const uint8_t *parameterSet;
      status = paramSetGetter(format, i, &parameterSet, &paramSize, NULL, NULL);
      if (status != noErr) {
        return [[FBControlCoreError
                 describe:[NSString stringWithFormat:@"Failed to get %@ parameter set at index %zu: %d", codecName, i, status]]
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

BOOL WriteFrameToAnnexBStream(CMSampleBufferRef sampleBuffer, id _Nullable context, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  (void)context;
  return WriteCodecFrameToAnnexBStream(sampleBuffer, CMVideoFormatDescriptionGetH264ParameterSetAtIndex, @"H264", consumer, logger, error);
}

BOOL WriteHEVCFrameToAnnexBStream(CMSampleBufferRef sampleBuffer, id _Nullable context, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  (void)context;
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

  uint16_t sectionLength = 14 + 4; // 14 bytes data (section[3..16]) + 4 CRC
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

NSData *FBMPEGTSPacketizePES(NSData *pesData,
                             BOOL isKeyFrame,
                             uint8_t streamType,
                             uint64_t pts90k,
                             uint8_t *videoContinuityCounter,
                             uint8_t *patContinuityCounter,
                             uint8_t *pmtContinuityCounter)
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
      packet[6] = (uint8_t)(pcrBase >> 25);
      packet[7] = (uint8_t)(pcrBase >> 17);
      packet[8] = (uint8_t)(pcrBase >> 9);
      packet[9] = (uint8_t)(pcrBase >> 1);
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
    (uint8_t)((id3PayloadLen >> 7) & 0x7F),
    (uint8_t)(id3PayloadLen & 0x7F),
  };
  [id3Tag appendBytes:id3Header length:10];

  // TXXX frame header
  uint8_t txxxHeader[10] = {
    'T', 'X', 'X', 'X',
    (uint8_t)((txxxPayloadLen >> 24) & 0xFF),
    (uint8_t)((txxxPayloadLen >> 16) & 0xFF),
    (uint8_t)((txxxPayloadLen >> 8) & 0xFF),
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
  pesHeader[9] = 0x21 | (uint8_t)(((pts90k >> 29) & 0x0E));
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
             describe:@"Sample Buffer is not ready"]
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
               describe:[NSString stringWithFormat:@"Failed to get %@ parameter set count %d", codecName, status]]
              failBool:error];
    }
    for (size_t i = 0; i < parameterSetCount; i++) {
      size_t paramSize;
      status = paramSetGetter(format, i, NULL, &paramSize, NULL, NULL);
      if (status != noErr) {
        return [[FBControlCoreError
                 describe:[NSString stringWithFormat:@"Failed to get %@ parameter set at index %zu: %d", codecName, i, status]]
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
  pesHeader[9] = 0x31 | (uint8_t)(((pts90k >> 29) & 0x0E));
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
             describe:[NSString stringWithFormat:@"Failed to copy block buffer data: %d", copyStatus]]
            failBool:error];
  }

  // Packetize into MPEG-TS and write to consumer
  NSData *tsData = FBMPEGTSPacketizePES(
    pesPacket,
    isKeyFrame,
    mpegtsStreamType,
    pts90k,
    &videoContinuityCounter,
    &patContinuityCounter,
    &pmtContinuityCounter
  );
  [consumer consumeData:tsData];

  return YES;
}

BOOL WriteHEVCFrameToMPEGTSStream(CMSampleBufferRef sampleBuffer, id _Nullable context, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  (void)context;
  return WriteCodecFrameToMPEGTSStream(sampleBuffer, CMVideoFormatDescriptionGetHEVCParameterSetAtIndex, @"HEVC", HEVCStreamType, consumer, logger, error);
}

BOOL WriteH264FrameToMPEGTSStream(CMSampleBufferRef sampleBuffer, id _Nullable context, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error)
{
  (void)context;
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

#pragma mark - Fragmented MP4 (fMP4) Writer

// ISO BMFF box helpers — all values are big-endian per spec.

static void FBFMP4Write8(NSMutableData *data, uint8_t value)
{
  [data appendBytes:&value length:1];
}

static void FBFMP4Write16(NSMutableData *data, uint16_t value)
{
  uint16_t be = CFSwapInt16HostToBig(value);
  [data appendBytes:&be length:2];
}

static void FBFMP4Write32(NSMutableData *data, uint32_t value)
{
  uint32_t be = CFSwapInt32HostToBig(value);
  [data appendBytes:&be length:4];
}

static void FBFMP4Write64(NSMutableData *data, uint64_t value)
{
  uint64_t be = CFSwapInt64HostToBig(value);
  [data appendBytes:&be length:8];
}

static NSUInteger FBFMP4BeginBox(NSMutableData *data, const char *type)
{
  NSUInteger offset = data.length;
  FBFMP4Write32(data, 0);
  [data appendBytes:type length:4];
  return offset;
}

static void FBFMP4EndBox(NSMutableData *data, NSUInteger sizeOffset)
{
  uint32_t size = (uint32_t)(data.length - sizeOffset);
  uint32_t be = CFSwapInt32HostToBig(size);
  [data replaceBytesInRange:NSMakeRange(sizeOffset, 4) withBytes:&be];
}

static void FBFMP4WriteFullBoxHeader(NSMutableData *data, uint8_t version, uint32_t flags)
{
  uint32_t vf = ((uint32_t)version << 24) | (flags & 0x00FFFFFF);
  FBFMP4Write32(data, vf);
}

static void FBFMP4WriteZeros(NSMutableData *data, NSUInteger count)
{
  NSCAssert(count <= 64, @"Zero count greater than 64");
  uint8_t zeros[64] = {0};
  [data appendBytes:zeros length:count];
}

// Extract codec configuration atom (avcC or hvcC) from CMFormatDescription.
static NSData *FBFMP4GetCodecConfigAtom(CMFormatDescriptionRef formatDescription, BOOL isHEVC)
{
  NSDictionary *atoms = (__bridge NSDictionary *)CMFormatDescriptionGetExtension(
    formatDescription,
    kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms
  );
  if (atoms) {
    NSString *key = isHEVC ? @"hvcC" : @"avcC";
    NSData *configData = atoms[key];
    if (configData) {
      return configData;
    }
  }
  // Fallback: build avcC/hvcC manually from parameter sets.
  NSMutableData *config = [NSMutableData new];
  if (!isHEVC) {
    const uint8_t *sps = NULL;
    size_t spsSize = 0;
    size_t paramCount = 0;
    OSStatus status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
      formatDescription,
      0,
      &sps,
      &spsSize,
      &paramCount,
      NULL
    );
    if (status != noErr || spsSize < 4) {
      return nil;
    }

    const uint8_t *pps = NULL;
    size_t ppsSize = 0;
    if (paramCount > 1) {
      CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        formatDescription,
        1,
        &pps,
        &ppsSize,
        NULL,
        NULL
      );
    }

    FBFMP4Write8(config, 1);
    FBFMP4Write8(config, sps[1]);
    FBFMP4Write8(config, sps[2]);
    FBFMP4Write8(config, sps[3]);
    FBFMP4Write8(config, 0xFF);
    FBFMP4Write8(config, 0xE1);
    FBFMP4Write16(config, (uint16_t)spsSize);
    [config appendBytes:sps length:spsSize];
    FBFMP4Write8(config, pps ? 1 : 0);
    if (pps) {
      FBFMP4Write16(config, (uint16_t)ppsSize);
      [config appendBytes:pps length:ppsSize];
    }
  } else {
    size_t paramCount = 0;
    OSStatus status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
      formatDescription,
      0,
      NULL,
      NULL,
      &paramCount,
      NULL
    );
    if (status != noErr) {
      return nil;
    }

    NSMutableArray<NSData *> *paramSets = [NSMutableArray new];
    NSMutableArray<NSNumber *> *paramTypes = [NSMutableArray new];
    for (size_t i = 0; i < paramCount; i++) {
      const uint8_t *ps = NULL;
      size_t psSize = 0;
      CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
        formatDescription,
        i,
        &ps,
        &psSize,
        NULL,
        NULL
      );
      if (ps && psSize > 0) {
        [paramSets addObject:[NSData dataWithBytes:ps length:psSize]];
        uint8_t nalType = (ps[0] >> 1) & 0x3F;
        [paramTypes addObject:@(nalType)];
      }
    }

    FBFMP4Write8(config, 1);
    FBFMP4Write8(config, 0);
    FBFMP4Write32(config, 0);
    FBFMP4Write16(config, 0);
    FBFMP4Write32(config, 0);
    FBFMP4Write8(config, 0);
    FBFMP4Write16(config, 0xF000);
    FBFMP4Write8(config, 0xFC);
    FBFMP4Write8(config, 0xFC);
    FBFMP4Write8(config, 0xF8);
    FBFMP4Write8(config, 0xF8);
    FBFMP4Write16(config, 0);
    FBFMP4Write8(config, 0x0F);

    NSMutableDictionary<NSNumber *, NSMutableArray<NSData *> *> *grouped = [NSMutableDictionary new];
    for (NSUInteger i = 0; i < paramSets.count; i++) {
      NSNumber *type = paramTypes[i];
      if (!grouped[type]) {
        grouped[type] = [NSMutableArray new];
      }
      [grouped[type] addObject:paramSets[i]];
    }

    FBFMP4Write8(config, (uint8_t)grouped.count);
    for (NSNumber *nalType in grouped) {
      NSArray<NSData *> *sets = grouped[nalType];
      FBFMP4Write8(config, nalType.unsignedCharValue & 0x3F);
      FBFMP4Write16(config, (uint16_t)sets.count);
      for (NSData *set in sets) {
        FBFMP4Write16(config, (uint16_t)set.length);
        [config appendData:set];
      }
    }
  }
  return config;
}

static NSData *FBFMP4CreateFtypBox(BOOL isHEVC)
{
  NSMutableData *data = [NSMutableData dataWithCapacity:24];
  NSUInteger off = FBFMP4BeginBox(data, "ftyp");
  [data appendBytes:"isom" length:4];
  FBFMP4Write32(data, 0x200);
  [data appendBytes:"isom" length:4];
  [data appendBytes:"iso6" length:4];
  if (isHEVC) {
    [data appendBytes:"hvc1" length:4];
  } else {
    [data appendBytes:"mp41" length:4];
  }
  FBFMP4EndBox(data, off);
  return data;
}

static NSData *FBFMP4CreateMoovBox(CMFormatDescriptionRef formatDescription,
                                   BOOL isHEVC,
                                   uint32_t width,
                                   uint32_t height,
                                   uint32_t timescale)
{
  NSMutableData *data = [NSMutableData dataWithCapacity:512];

  NSData *codecConfig = FBFMP4GetCodecConfigAtom(formatDescription, isHEVC);
  const char *sampleEntryType = isHEVC ? "hvc1" : "avc1";
  const char *codecConfigType = isHEVC ? "hvcC" : "avcC";

  NSUInteger moovOff = FBFMP4BeginBox(data, "moov");

  // mvhd
  {
    NSUInteger off = FBFMP4BeginBox(data, "mvhd");
    FBFMP4WriteFullBoxHeader(data, 0, 0);
    FBFMP4Write32(data, 0);
    FBFMP4Write32(data, 0);
    FBFMP4Write32(data, timescale);
    FBFMP4Write32(data, 0);
    FBFMP4Write32(data, 0x00010000);
    FBFMP4Write16(data, 0x0100);
    FBFMP4WriteZeros(data, 10);
    uint32_t matrix[] = {0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000};
    for (int i = 0; i < 9; i++) {
      FBFMP4Write32(data, matrix[i]);
    }
    FBFMP4WriteZeros(data, 24);
    FBFMP4Write32(data, 2);
    FBFMP4EndBox(data, off);
  }

  // trak
  {
    NSUInteger trakOff = FBFMP4BeginBox(data, "trak");

    // tkhd
    {
      NSUInteger off = FBFMP4BeginBox(data, "tkhd");
      FBFMP4WriteFullBoxHeader(data, 0, 0x03);
      FBFMP4Write32(data, 0);
      FBFMP4Write32(data, 0);
      FBFMP4Write32(data, 1);
      FBFMP4Write32(data, 0);
      FBFMP4Write32(data, 0);
      FBFMP4WriteZeros(data, 8);
      FBFMP4Write16(data, 0);
      FBFMP4Write16(data, 0);
      FBFMP4Write16(data, 0);
      FBFMP4Write16(data, 0);
      uint32_t matrix[] = {0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000};
      for (int i = 0; i < 9; i++) {
        FBFMP4Write32(data, matrix[i]);
      }
      FBFMP4Write32(data, width << 16);
      FBFMP4Write32(data, height << 16);
      FBFMP4EndBox(data, off);
    }

    // mdia
    {
      NSUInteger mdiaOff = FBFMP4BeginBox(data, "mdia");

      // mdhd
      {
        NSUInteger off = FBFMP4BeginBox(data, "mdhd");
        FBFMP4WriteFullBoxHeader(data, 0, 0);
        FBFMP4Write32(data, 0);
        FBFMP4Write32(data, 0);
        FBFMP4Write32(data, timescale);
        FBFMP4Write32(data, 0);
        FBFMP4Write16(data, 0x55C4);
        FBFMP4Write16(data, 0);
        FBFMP4EndBox(data, off);
      }

      // hdlr
      {
        NSUInteger off = FBFMP4BeginBox(data, "hdlr");
        FBFMP4WriteFullBoxHeader(data, 0, 0);
        FBFMP4Write32(data, 0);
        [data appendBytes:"vide" length:4];
        FBFMP4WriteZeros(data, 12);
        const char *name = "VideoHandler";
        [data appendBytes:name length:strlen(name) + 1];
        FBFMP4EndBox(data, off);
      }

      // minf
      {
        NSUInteger minfOff = FBFMP4BeginBox(data, "minf");

        // vmhd
        {
          NSUInteger off = FBFMP4BeginBox(data, "vmhd");
          FBFMP4WriteFullBoxHeader(data, 0, 1);
          FBFMP4Write16(data, 0);
          FBFMP4WriteZeros(data, 6);
          FBFMP4EndBox(data, off);
        }

        // dinf → dref → url
        {
          NSUInteger dinfOff = FBFMP4BeginBox(data, "dinf");
          NSUInteger drefOff = FBFMP4BeginBox(data, "dref");
          FBFMP4WriteFullBoxHeader(data, 0, 0);
          FBFMP4Write32(data, 1);
          NSUInteger urlOff = FBFMP4BeginBox(data, "url ");
          FBFMP4WriteFullBoxHeader(data, 0, 1);
          FBFMP4EndBox(data, urlOff);
          FBFMP4EndBox(data, drefOff);
          FBFMP4EndBox(data, dinfOff);
        }

        // stbl
        {
          NSUInteger stblOff = FBFMP4BeginBox(data, "stbl");

          // stsd
          {
            NSUInteger stsdOff = FBFMP4BeginBox(data, "stsd");
            FBFMP4WriteFullBoxHeader(data, 0, 0);
            FBFMP4Write32(data, 1);

            // Visual sample entry (avc1 or hvc1)
            {
              NSUInteger entryOff = FBFMP4BeginBox(data, sampleEntryType);
              FBFMP4WriteZeros(data, 6);
              FBFMP4Write16(data, 1);
              FBFMP4WriteZeros(data, 16);
              FBFMP4Write16(data, (uint16_t)width);
              FBFMP4Write16(data, (uint16_t)height);
              FBFMP4Write32(data, 0x00480000);
              FBFMP4Write32(data, 0x00480000);
              FBFMP4Write32(data, 0);
              FBFMP4Write16(data, 1);
              FBFMP4WriteZeros(data, 32);
              FBFMP4Write16(data, 0x0018);
              FBFMP4Write16(data, 0xFFFF);

              if (codecConfig) {
                NSUInteger ccOff = FBFMP4BeginBox(data, codecConfigType);
                [data appendData:codecConfig];
                FBFMP4EndBox(data, ccOff);
              }

              FBFMP4EndBox(data, entryOff);
            }

            FBFMP4EndBox(data, stsdOff);
          }

          // Empty required boxes
          {
            NSUInteger off;
            off = FBFMP4BeginBox(data, "stts");
            FBFMP4WriteFullBoxHeader(data, 0, 0);
            FBFMP4Write32(data, 0);
            FBFMP4EndBox(data, off);

            off = FBFMP4BeginBox(data, "stsc");
            FBFMP4WriteFullBoxHeader(data, 0, 0);
            FBFMP4Write32(data, 0);
            FBFMP4EndBox(data, off);

            off = FBFMP4BeginBox(data, "stsz");
            FBFMP4WriteFullBoxHeader(data, 0, 0);
            FBFMP4Write32(data, 0);
            FBFMP4Write32(data, 0);
            FBFMP4EndBox(data, off);

            off = FBFMP4BeginBox(data, "stco");
            FBFMP4WriteFullBoxHeader(data, 0, 0);
            FBFMP4Write32(data, 0);
            FBFMP4EndBox(data, off);
          }

          FBFMP4EndBox(data, stblOff);
        }

        FBFMP4EndBox(data, minfOff);
      }

      FBFMP4EndBox(data, mdiaOff);
    }

    FBFMP4EndBox(data, trakOff);
  }

  // mvex
  {
    NSUInteger mvexOff = FBFMP4BeginBox(data, "mvex");
    NSUInteger trexOff = FBFMP4BeginBox(data, "trex");
    FBFMP4WriteFullBoxHeader(data, 0, 0);
    FBFMP4Write32(data, 1);
    FBFMP4Write32(data, 1);
    FBFMP4Write32(data, 0);
    FBFMP4Write32(data, 0);
    FBFMP4Write32(data, 0);
    FBFMP4EndBox(data, trexOff);
    FBFMP4EndBox(data, mvexOff);
  }

  FBFMP4EndBox(data, moovOff);
  return data;
}

// Build the moof + mdat header for a single-sample fragment.
// The sample data itself is NOT included — the caller emits it separately
// to avoid a redundant copy of the (potentially large) video frame payload.
// The returned NSData ends just after the mdat box header; the caller must
// append exactly `sampleSize` bytes of sample data, then the fragment is complete.
static NSData *FBFMP4CreateFragmentHeader(uint32_t sequenceNumber,
                                          uint64_t baseDecodeTime,
                                          uint32_t duration,
                                          uint32_t sampleSize,
                                          BOOL isKeyFrame)
{
  uint32_t trunFlags = 0x000701;
  // trun: header(12) + data_offset(4) + 1 sample entry (duration(4) + size(4) + flags(4))
  size_t trunSize = 12 + 4 + 12;
  size_t moofSize = 8 + 16 + 8 + 16 + 20 + trunSize;
  size_t mdatHeaderSize = 8;

  NSMutableData *data = [NSMutableData dataWithCapacity:moofSize + mdatHeaderSize];

  NSUInteger moofOff = FBFMP4BeginBox(data, "moof");

  // mfhd
  {
    NSUInteger off = FBFMP4BeginBox(data, "mfhd");
    FBFMP4WriteFullBoxHeader(data, 0, 0);
    FBFMP4Write32(data, sequenceNumber);
    FBFMP4EndBox(data, off);
  }

  // traf
  {
    NSUInteger trafOff = FBFMP4BeginBox(data, "traf");

    // tfhd
    {
      NSUInteger off = FBFMP4BeginBox(data, "tfhd");
      FBFMP4WriteFullBoxHeader(data, 0, 0x020000);
      FBFMP4Write32(data, 1);
      FBFMP4EndBox(data, off);
    }

    // tfdt
    {
      NSUInteger off = FBFMP4BeginBox(data, "tfdt");
      FBFMP4WriteFullBoxHeader(data, 1, 0);
      FBFMP4Write64(data, baseDecodeTime);
      FBFMP4EndBox(data, off);
    }

    // trun — single sample
    {
      FBFMP4BeginBox(data, "trun");
      FBFMP4WriteFullBoxHeader(data, 0, trunFlags);
      FBFMP4Write32(data, 1); // sample_count = 1
      FBFMP4Write32(data, 0); // placeholder for data_offset (patched below)
      FBFMP4Write32(data, duration);
      FBFMP4Write32(data, sampleSize);
      FBFMP4Write32(data, isKeyFrame ? 0x02000000 : 0x01010000);
    }

    FBFMP4EndBox(data, trafOff);
  }

  FBFMP4EndBox(data, moofOff);

  // Patch data_offset: distance from moof start to first sample byte in mdat.
  uint32_t actualMoofSize = (uint32_t)(data.length - moofOff);
  uint32_t dataOffset = actualMoofSize + (uint32_t)mdatHeaderSize;
  // dataOffsetPos = moofOff + moof_header(8) + mfhd(16) + traf_header(8) + tfhd(16) + tfdt(20) + trun_header(12) + sample_count(4)
  NSUInteger patchPos = moofOff + 8 + 16 + 8 + 16 + 20 + 12 + 4;
  uint32_t dataOffsetBE = CFSwapInt32HostToBig(dataOffset);
  [data replaceBytesInRange:NSMakeRange(patchPos, 4) withBytes:&dataOffsetBE];

  // mdat header only — caller appends sample data.
  FBFMP4Write32(data, (uint32_t)(mdatHeaderSize + sampleSize));
  [data appendBytes:"mdat" length:4];

  return data;
}

// FBFMP4MuxerContext — minimal per-stream state holder for fMP4 writers.

@implementation FBFMP4MuxerContext

- (instancetype)initWithHEVC:(BOOL)isHEVC
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _isHEVC = isHEVC;
  _initWritten = NO;
  _sequenceNumber = 0;
  _baseDecodeTime = 0;
  _lastPts90k = 0;

  return self;
}

@end

// Per-frame fMP4 writer: each frame is immediately emitted as a single-sample moof+mdat fragment.

static BOOL WriteCodecFrameToFMP4Stream(CMSampleBufferRef sampleBuffer,
                                        id _Nullable context,
                                        id<FBDataConsumer> consumer,
                                        id<FBControlCoreLogger> logger,
                                        NSError **error)
{
  FBFMP4MuxerContext *ctx = (FBFMP4MuxerContext *)context;
  if (!ctx) {
    return [[FBControlCoreError describe:@"fMP4 writer called without context"] failBool:error];
  }

  if (!CMSampleBufferDataIsReady(sampleBuffer)) {
    return [[FBControlCoreError describe:@"Sample Buffer is not ready"] failBool:error];
  }

  // Detect keyframe.
  bool isKeyFrame = false;
  CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
  if (CFArrayGetCount(attachments)) {
    CFDictionaryRef attachment = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    isKeyFrame = !CFDictionaryContainsKey(attachment, kCMSampleAttachmentKey_NotSync);
  }

  // Extract PTS.
  CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
  uint64_t pts90k = (uint64_t)(CMTimeGetSeconds(pts) * 90000.0);
  uint64_t prevPts90k = ctx.lastPts90k;
  ctx.lastPts90k = pts90k;

  // On first keyframe: emit init segment (ftyp + moov).
  if (!ctx.initWritten) {
    if (!isKeyFrame) {
      return YES; // Drop frames before first keyframe.
    }

    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(formatDesc);

    NSData *ftyp = FBFMP4CreateFtypBox(ctx.isHEVC);
    NSData *moov = FBFMP4CreateMoovBox(
      formatDesc,
      ctx.isHEVC,
      (uint32_t)dims.width,
      (uint32_t)dims.height,
      90000
    );

    [consumer consumeData:ftyp];
    [consumer consumeData:moov];

    ctx.initWritten = YES;
    ctx.baseDecodeTime = pts90k;
    [logger log:[NSString stringWithFormat:@"fMP4 init segment written (%dx%d, %s)",
                 dims.width, dims.height, ctx.isHEVC ? "HEVC" : "H264"]];
  }

  // Compute duration.
  uint32_t duration90k;
  CMTime sampleDuration = CMSampleBufferGetDuration(sampleBuffer);
  if (CMTIME_IS_VALID(sampleDuration) && CMTimeGetSeconds(sampleDuration) > 0) {
    duration90k = (uint32_t)(CMTimeGetSeconds(sampleDuration) * 90000.0);
  } else if (prevPts90k > 0 && pts90k > prevPts90k) {
    duration90k = (uint32_t)(pts90k - prevPts90k);
  } else {
    duration90k = 3000; // ~33ms at 30fps fallback
  }

  // Get AVCC NAL data (do NOT convert to Annex-B).
  CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
  size_t dataLength = CMBlockBufferGetDataLength(dataBuffer);

  // Emit moof + mdat header, then sample data — single copy only.
  ctx.sequenceNumber += 1;
  NSData *header = FBFMP4CreateFragmentHeader(
    ctx.sequenceNumber,
    ctx.baseDecodeTime,
    duration90k,
    (uint32_t)dataLength,
    isKeyFrame
  );
  [consumer consumeData:header];

  // Try zero-copy via CMBlockBufferGetDataPointer (works when buffer is contiguous).
  char *dataPointer = NULL;
  size_t lengthAtOffset = 0;
  OSStatus ptrStatus = CMBlockBufferGetDataPointer(dataBuffer, 0, &lengthAtOffset, NULL, &dataPointer);
  if (ptrStatus == noErr && dataPointer && lengthAtOffset >= dataLength) {
    [consumer consumeData:[NSData dataWithBytesNoCopy:dataPointer length:dataLength freeWhenDone:NO]];
  } else {
    // Fallback: copy when the block buffer is non-contiguous.
    NSMutableData *sampleData = [NSMutableData dataWithLength:dataLength];
    OSStatus copyStatus = CMBlockBufferCopyDataBytes(dataBuffer, 0, dataLength, sampleData.mutableBytes);
    if (copyStatus != noErr) {
      return [[FBControlCoreError
               describe:[NSString stringWithFormat:@"Failed to copy block buffer data: %d", copyStatus]]
              failBool:error];
    }
    [consumer consumeData:sampleData];
  }

  ctx.baseDecodeTime += duration90k;

  return YES;
}

BOOL WriteH264FrameToFMP4Stream(CMSampleBufferRef sampleBuffer,
                                id _Nullable context,
                                id<FBDataConsumer> consumer,
                                id<FBControlCoreLogger> logger,
                                NSError **error)
{
  return WriteCodecFrameToFMP4Stream(sampleBuffer, context, consumer, logger, error);
}

BOOL WriteHEVCFrameToFMP4Stream(CMSampleBufferRef sampleBuffer,
                                id _Nullable context,
                                id<FBDataConsumer> consumer,
                                id<FBControlCoreLogger> logger,
                                NSError **error)
{
  return WriteCodecFrameToFMP4Stream(sampleBuffer, context, consumer, logger, error);
}

void FBFMP4WriteEmsgBox(FBFMP4MuxerContext *context, NSString *text, id<FBDataConsumer> consumer)
{
  NSData *textData = [text dataUsingEncoding:NSUTF8StringEncoding];
  if (!textData) {
    return;
  }

  NSMutableData *data = [NSMutableData dataWithCapacity:64 + textData.length];

  NSUInteger off = FBFMP4BeginBox(data, "emsg");
  FBFMP4WriteFullBoxHeader(data, 1, 0);
  FBFMP4Write32(data, 90000);
  FBFMP4Write64(data, context.lastPts90k);
  FBFMP4Write32(data, 0);
  FBFMP4Write32(data, 0);

  const char *scheme = "urn:sime2e:chapter";
  [data appendBytes:scheme length:strlen(scheme) + 1];
  uint8_t zero = 0;
  [data appendBytes:&zero length:1];
  [data appendData:textData];

  FBFMP4EndBox(data, off);

  [consumer consumeData:data];
}

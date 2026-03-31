/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBVideoStreamTestDoubles.h"

#import <VideoToolbox/VideoToolbox.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorVideoStream_Testing.h>

#pragma mark - FBCapturingLogger

@implementation FBCapturingLogger

- (instancetype)init
{
  self = [super init];
  if (self) {
    _messages = [NSMutableArray array];
  }
  return self;
}

- (id<FBControlCoreLogger>)log:(NSString *)string
{
  [self.messages addObject:string];
  return self;
}

- (id<FBControlCoreLogger>)logFormat:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  [self.messages addObject:message];
  return self;
}

- (id<FBControlCoreLogger>)info { return self; }

- (id<FBControlCoreLogger>)debug { return self; }

- (id<FBControlCoreLogger>)error { return self; }

- (id<FBControlCoreLogger>)withName:(NSString *)prefix { return self; }

- (id<FBControlCoreLogger>)withDateFormatEnabled:(BOOL)enabled { return self; }

- (NSString *)name { return nil; }

- (FBControlCoreLogLevel)level { return FBControlCoreLogLevelMultiple; }

@end

#pragma mark - Sample Buffer Helpers

CMSampleBufferRef CreateH264SampleBuffer(void)
{
  const uint8_t sps[] = {0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2};
  const uint8_t pps[] = {0x68, 0xce, 0x38, 0x80};
  const uint8_t *paramSets[] = {sps, pps};
  size_t paramSizes[] = {sizeof(sps), sizeof(pps)};

  CMFormatDescriptionRef formatDesc = NULL;
  OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
    NULL,
    2,
    paramSets,
    paramSizes,
    4,
    &formatDesc
  );
  NSCAssert(status == noErr, @"Failed to create H264 format description: %d", (int)status);

  static uint8_t avccData[] = {
    0x00, 0x00, 0x00, 0x05,
    0x65, 0x88, 0x80, 0x40, 0x00
  };

  CMBlockBufferRef blockBuf = NULL;
  status = CMBlockBufferCreateWithMemoryBlock(
    NULL,
    avccData,
    sizeof(avccData),
    kCFAllocatorNull,
    NULL,
    0,
    sizeof(avccData),
    0,
    &blockBuf
  );
  NSCAssert(status == noErr, @"Failed to create block buffer: %d", (int)status);

  CMSampleBufferRef sampleBuf = NULL;
  size_t sampleSize = sizeof(avccData);
  CMSampleTimingInfo timing = {
    .duration = CMTimeMake(1, 30),
    .presentationTimeStamp = CMTimeMake(0, 90000),
    .decodeTimeStamp = kCMTimeInvalid
  };
  status = CMSampleBufferCreate(
    NULL,
    blockBuf,
    true,
    NULL,
    NULL,
    formatDesc,
    1,
    1,
    &timing,
    1,
    &sampleSize,
    &sampleBuf
  );
  NSCAssert(status == noErr, @"Failed to create sample buffer: %d", (int)status);

  CFRelease(formatDesc);
  CFRelease(blockBuf);

  return sampleBuf;
}

FBSimulatorVideoStreamFramePusher_VideoToolbox *CreateTestVideoStreamPusher(id<FBControlCoreLogger> logger)
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc] initWithFormat:[FBVideoStreamFormat compressedVideoWithCodec:FBVideoStreamCodecH264 transport:FBVideoStreamTransportAnnexB]
                                                                          framesPerSecond:@30
                                                                              rateControl:nil
                                                                              scaleFactor:nil
                                                                             keyFrameRate:@10.0];
  id<FBDataConsumer> consumer = [FBDataBuffer accumulatingBuffer];
  return [[FBSimulatorVideoStreamFramePusher_VideoToolbox alloc]
          initWithConfiguration:config
          compressionSessionProperties:@{}
          videoCodec:kCMVideoCodecType_H264
          consumer:consumer
          compressorCallback:NULL
          frameWriter:WriteFrameToAnnexBStream
          frameWriterContext:nil
          logger:logger];
}

void HandleCompressedSampleBufferNullable(FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher,
                                          CMSampleBufferRef _Nullable sampleBuffer,
                                          OSStatus encodeStatus,
                                          VTEncodeInfoFlags infoFlags)
{
  [pusher handleCompressedSampleBuffer:sampleBuffer encodeStatus:encodeStatus infoFlags:infoFlags];
}

CMSampleBufferRef CreateNotReadySampleBuffer(void)
{
  const uint8_t sps[] = {0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2};
  const uint8_t pps[] = {0x68, 0xce, 0x38, 0x80};
  const uint8_t *paramSets[] = {sps, pps};
  size_t paramSizes[] = {sizeof(sps), sizeof(pps)};

  CMFormatDescriptionRef formatDesc = NULL;
  OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
    NULL,
    2,
    paramSets,
    paramSizes,
    4,
    &formatDesc
  );
  NSCAssert(status == noErr, @"Failed to create H264 format description: %d", (int)status);

  static uint8_t avccData[] = {
    0x00, 0x00, 0x00, 0x05,
    0x65, 0x88, 0x80, 0x40, 0x00
  };

  CMBlockBufferRef blockBuf = NULL;
  status = CMBlockBufferCreateWithMemoryBlock(
    NULL,
    avccData,
    sizeof(avccData),
    kCFAllocatorNull,
    NULL,
    0,
    sizeof(avccData),
    0,
    &blockBuf
  );
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
    NULL,
    blockBuf,
    false,
    NULL,
    NULL,
    formatDesc,
    1,
    1,
    &timing,
    1,
    &sampleSize,
    &sampleBuf
  );
  NSCAssert(status == noErr, @"Failed to create sample buffer: %d", (int)status);

  CFRelease(formatDesc);
  CFRelease(blockBuf);

  return sampleBuf;
}

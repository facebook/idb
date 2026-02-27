/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorVideoStream_Testing.h>

#pragma mark - Test Doubles

@interface FBCapturingLogger : NSObject <FBControlCoreLogger>
@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *messages;
@end

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

#pragma mark - Helpers

static CMSampleBufferRef CreateH264SampleBuffer(void)
{
  const uint8_t sps[] = {0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2};
  const uint8_t pps[] = {0x68, 0xce, 0x38, 0x80};
  const uint8_t *paramSets[] = {sps, pps};
  size_t paramSizes[] = {sizeof(sps), sizeof(pps)};

  CMFormatDescriptionRef formatDesc = NULL;
  OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
    NULL, 2, paramSets, paramSizes, 4, &formatDesc);
  NSCAssert(status == noErr, @"Failed to create H264 format description: %d", (int)status);

  static uint8_t avccData[] = {
    0x00, 0x00, 0x00, 0x05,
    0x65, 0x88, 0x80, 0x40, 0x00
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

  CFRelease(formatDesc);
  CFRelease(blockBuf);

  return sampleBuf;
}

static CMSampleBufferRef CreateNotReadySampleBuffer(void)
{
  const uint8_t sps[] = {0x67, 0x42, 0x00, 0x0a, 0xf8, 0x41, 0xa2};
  const uint8_t pps[] = {0x68, 0xce, 0x38, 0x80};
  const uint8_t *paramSets[] = {sps, pps};
  size_t paramSizes[] = {sizeof(sps), sizeof(pps)};

  CMFormatDescriptionRef formatDesc = NULL;
  OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
    NULL, 2, paramSets, paramSizes, 4, &formatDesc);
  NSCAssert(status == noErr, @"Failed to create H264 format description: %d", (int)status);

  static uint8_t avccData[] = {
    0x00, 0x00, 0x00, 0x05,
    0x65, 0x88, 0x80, 0x40, 0x00
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

@interface FBSimulatorVideoStreamCallbackTests : XCTestCase
@end

@implementation FBSimulatorVideoStreamCallbackTests

- (FBSimulatorVideoStreamFramePusher_VideoToolbox *)createPusherWithLogger:(FBCapturingLogger *)logger
{
  FBVideoStreamConfiguration *config = [[FBVideoStreamConfiguration alloc]
    initWithEncoding:FBVideoStreamEncodingH264
    framesPerSecond:@30
    compressionQuality:@0.2
    scaleFactor:nil
    avgBitrate:nil
    keyFrameRate:@10.0];
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  return [[FBSimulatorVideoStreamFramePusher_VideoToolbox alloc]
    initWithConfiguration:config
    compressionSessionProperties:@{}
    videoCodec:kCMVideoCodecType_H264
    consumer:consumer
    compressorCallback:NULL
    frameWriter:WriteFrameToAnnexBStream
    logger:logger];
}

- (void)testWarmupFramesSuppressed
{
  FBCapturingLogger *logger = [[FBCapturingLogger alloc] init];
  FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher = [self createPusherWithLogger:logger];

  // Send 5 not-ready buffers (simulates warmup)
  for (NSUInteger i = 0; i < 5; i++) {
    CMSampleBufferRef notReady = CreateNotReadySampleBuffer();
    [pusher handleCompressedSampleBuffer:notReady encodeStatus:noErr infoFlags:0];
    CFRelease(notReady);
  }

  // No per-frame messages during warmup
  for (NSString *msg in logger.messages) {
    XCTAssertFalse([msg containsString:@"Sample Buffer is not ready"], @"Should not log per-frame not-ready messages during warmup");
  }

  // Now send a ready buffer to complete warmup
  CMSampleBufferRef ready = CreateH264SampleBuffer();
  [pusher handleCompressedSampleBuffer:ready encodeStatus:noErr infoFlags:0];
  CFRelease(ready);

  // Should have a single warmup message
  NSUInteger warmupMessageCount = 0;
  for (NSString *msg in logger.messages) {
    if ([msg containsString:@"Encoder warmed up after 5 skipped frames"]) {
      warmupMessageCount++;
    }
  }
  XCTAssertEqual(warmupMessageCount, 1u, @"Should log exactly one warmup completion message");
  XCTAssertTrue(pusher.warmupComplete);
}

- (void)testStarvationDetectedDuringWarmup
{
  FBCapturingLogger *logger = [[FBCapturingLogger alloc] init];
  FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher = [self createPusherWithLogger:logger];

  // Send 20 not-ready buffers without any success
  for (NSUInteger i = 0; i < 20; i++) {
    CMSampleBufferRef notReady = CreateNotReadySampleBuffer();
    [pusher handleCompressedSampleBuffer:notReady encodeStatus:noErr infoFlags:0];
    CFRelease(notReady);
  }

  BOOL foundStarvationWarning = NO;
  for (NSString *msg in logger.messages) {
    if ([msg containsString:@"has not produced a frame after 20 attempts"]) {
      foundStarvationWarning = YES;
    }
  }
  XCTAssertTrue(foundStarvationWarning, @"Should warn about possible starvation after 20 warmup frames");
  XCTAssertTrue(pusher.starvationWarningLogged);
}

- (void)testPostWarmupStarvation
{
  FBCapturingLogger *logger = [[FBCapturingLogger alloc] init];
  FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher = [self createPusherWithLogger:logger];

  // First, complete warmup with a ready buffer
  CMSampleBufferRef ready = CreateH264SampleBuffer();
  [pusher handleCompressedSampleBuffer:ready encodeStatus:noErr infoFlags:0];
  CFRelease(ready);
  XCTAssertTrue(pusher.warmupComplete);

  // Now send 10 not-ready buffers post-warmup
  for (NSUInteger i = 0; i < 10; i++) {
    CMSampleBufferRef notReady = CreateNotReadySampleBuffer();
    [pusher handleCompressedSampleBuffer:notReady encodeStatus:noErr infoFlags:0];
    CFRelease(notReady);
  }

  BOOL foundStarvationWarning = NO;
  for (NSString *msg in logger.messages) {
    if ([msg containsString:@"Encoder starvation: 10 consecutive frames not ready after warmup"]) {
      foundStarvationWarning = YES;
    }
  }
  XCTAssertTrue(foundStarvationWarning, @"Should warn about post-warmup starvation after 10 consecutive failures");
  XCTAssertTrue(pusher.starvationWarningLogged);
}

- (void)testEncodeErrorLogged
{
  FBCapturingLogger *logger = [[FBCapturingLogger alloc] init];
  FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher = [self createPusherWithLogger:logger];

  [pusher handleCompressedSampleBuffer:NULL encodeStatus:-12345 infoFlags:0];

  BOOL foundError = NO;
  for (NSString *msg in logger.messages) {
    if ([msg containsString:@"VideoToolbox encode error: OSStatus -12345"]) {
      foundError = YES;
    }
  }
  XCTAssertTrue(foundError, @"Should log VideoToolbox encode error with status code");
  XCTAssertEqual(pusher.totalCallbackFrameCount, 1u);
}

- (void)testFrameDroppedCountedAsFailure
{
  FBCapturingLogger *logger = [[FBCapturingLogger alloc] init];
  FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher = [self createPusherWithLogger:logger];

  [pusher handleCompressedSampleBuffer:NULL encodeStatus:noErr infoFlags:kVTEncodeInfo_FrameDropped];

  // Dropped frame should increment failure counter, not produce a per-frame log
  XCTAssertEqual(pusher.consecutiveNotReadyFrameCount, 1u);
  XCTAssertEqual(pusher.totalCallbackFrameCount, 1u);
  XCTAssertEqual(logger.messages.count, 0u, @"Single dropped frame should not produce a log message");
}

- (void)testDroppedFramesTriggersStarvationWarning
{
  FBCapturingLogger *logger = [[FBCapturingLogger alloc] init];
  FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher = [self createPusherWithLogger:logger];

  // Send 20 dropped frames — should trigger starvation warning
  for (NSUInteger i = 0; i < 20; i++) {
    [pusher handleCompressedSampleBuffer:NULL encodeStatus:noErr infoFlags:kVTEncodeInfo_FrameDropped];
  }

  BOOL foundStarvationWarning = NO;
  for (NSString *msg in logger.messages) {
    if ([msg containsString:@"has not produced a frame after 20 attempts"]) {
      foundStarvationWarning = YES;
    }
  }
  XCTAssertTrue(foundStarvationWarning, @"20 consecutive dropped frames should trigger starvation warning");
  XCTAssertEqual(logger.messages.count, 1u, @"Should produce exactly one starvation warning");
}

- (void)testNoWarmupMessageWhenFirstFrameSucceeds
{
  FBCapturingLogger *logger = [[FBCapturingLogger alloc] init];
  FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher = [self createPusherWithLogger:logger];

  // Send a ready buffer immediately
  CMSampleBufferRef ready = CreateH264SampleBuffer();
  [pusher handleCompressedSampleBuffer:ready encodeStatus:noErr infoFlags:0];
  CFRelease(ready);

  XCTAssertTrue(pusher.warmupComplete);

  // No warmup message should be logged
  for (NSString *msg in logger.messages) {
    XCTAssertFalse([msg containsString:@"Encoder warmed up"], @"Should not log warmup message when first frame succeeds immediately");
  }
}

@end

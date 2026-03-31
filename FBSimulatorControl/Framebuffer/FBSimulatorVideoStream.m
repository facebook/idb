/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorVideoStream.h"

#import <mach/mach_time.h>

#import <CoreImage/CoreImage.h>
#import <CoreVideo/CVPixelBufferIOSurface.h>
#import <CoreVideo/CoreVideo.h>
#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>
#import <VideoToolbox/VideoToolbox.h>

#import <FBControlCore/FBControlCore.h>

#import "FBPeriodicStatsTimer.h"
#import "FBSimulatorError.h"

typedef BOOL (*FBCompressedFrameWriter)(CMSampleBufferRef sampleBuffer, id _Nullable context, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

@interface FBVideoCompressorCallbackSourceFrame : NSObject

- (instancetype)initWithPixelBuffer:(CVPixelBufferRef)pixelBuffer frameNumber:(NSUInteger)frameNumber;
- (void)dealloc;

@property (nonatomic, readonly) NSUInteger frameNumber;
@property (nullable, nonatomic, readwrite, assign) CVPixelBufferRef pixelBuffer;

@end

@protocol FBSimulatorVideoStreamFramePusher <NSObject>

- (BOOL)setupWithPixelBuffer:(CVPixelBufferRef)pixelBuffer edgeInsets:(FBVideoStreamEdgeInsets)edgeInsets error:(NSError **)error;
- (BOOL)tearDown:(NSError **)error;
- (BOOL)writeEncodedFrame:(CVPixelBufferRef)pixelBuffer frameNumber:(NSUInteger)frameNumber timeAtFirstFrame:(CFTimeInterval)timeAtFirstFrame frameDuration:(CFTimeInterval)frameDuration forceKeyFrame:(BOOL)forceKeyFrame error:(NSError **)error;

@optional
- (FBVideoEncoderStats)currentStats;

@end

@interface FBSimulatorVideoStreamFramePusher_Bitmap : NSObject <FBSimulatorVideoStreamFramePusher>

- (instancetype)initWithConsumer:(id<FBDataConsumer>)consumer scaleFactor:(NSNumber *)scaleFactor;

@property (nonatomic, readonly, strong) id<FBDataConsumer> consumer;
/**
 The scale factor between 0-1. nil for no scaling.
 */
@property (nullable, nonatomic, readonly, copy) NSNumber *scaleFactor;
@property (nullable, nonatomic, readwrite, assign) CVPixelBufferPoolRef scaledPixelBufferPoolRef;
@property (nullable, nonatomic, readwrite, assign) VTPixelTransferSessionRef pixelTransferSession;

@end

@interface FBSimulatorVideoStreamFramePusher_VideoToolbox : NSObject <FBSimulatorVideoStreamFramePusher>

- (instancetype)initWithConfiguration:(FBVideoStreamConfiguration *)configuration compressionSessionProperties:(NSDictionary<NSString *, id> *)compressionSessionProperties videoCodec:(CMVideoCodecType)videoCodec consumer:(id<FBDataConsumer>)consumer compressorCallback:(VTCompressionOutputCallback)compressorCallback frameWriter:(FBCompressedFrameWriter)frameWriter frameWriterContext:(id _Nullable)frameWriterContext logger:(id<FBControlCoreLogger>)logger;

@property (nonatomic, readonly, copy) FBVideoStreamConfiguration *configuration;
@property (nullable, nonatomic, readwrite, assign) VTCompressionSessionRef compressionSession;
@property (nullable, nonatomic, readwrite, assign) CVPixelBufferPoolRef scaledPixelBufferPoolRef;
@property (nullable, nonatomic, readwrite, assign) CVPixelBufferPoolRef nv12PixelBufferPoolRef;
@property (nullable, nonatomic, readwrite, assign) VTPixelTransferSessionRef pixelTransferSession;
@property (nonatomic, readonly, assign) CMVideoCodecType videoCodec;
@property (nonatomic, readonly, assign) VTCompressionOutputCallback compressorCallback;
@property (nonatomic, readonly, assign) FBCompressedFrameWriter frameWriter;
@property (nullable, nonatomic, readonly, strong) id frameWriterContext;
@property (nonatomic, readonly, strong) id<FBControlCoreLogger> logger;
@property (nonatomic, readonly, strong) id<FBDataConsumer> consumer;
@property (nonatomic, readonly, strong) NSDictionary<NSString *, id> *compressionSessionProperties;

@end

@interface FBSimulatorVideoStreamFramePusher_VideoToolbox ()
@property (nonatomic, assign) NSUInteger consecutiveNotReadyFrameCount;
@property (nonatomic, assign) BOOL warmupComplete;
@property (nonatomic, assign) BOOL starvationWarningLogged;
@property (nonatomic, assign) FBVideoEncoderStats stats;
@property (nonatomic, assign) FBVideoEncoderStats lastLoggedStats;
@property (nonatomic, assign) FBPeriodicStatsTimer statsTimer;
- (void)handleCompressedSampleBuffer:(CMSampleBufferRef)sampleBuffer
                        encodeStatus:(OSStatus)encodeStatus
                           infoFlags:(VTEncodeInfoFlags)infoFlags;
@end

static CVPixelBufferPoolRef createScaledPixelBufferPool(CVPixelBufferRef sourceBuffer, NSNumber *scaleFactor)
{
  size_t sourceWidth = CVPixelBufferGetWidth(sourceBuffer);
  size_t sourceHeight = CVPixelBufferGetHeight(sourceBuffer);

  size_t destinationWidth = (size_t) floor(scaleFactor.doubleValue * (double)sourceWidth);
  size_t destinationHeight = (size_t) floor(scaleFactor.doubleValue * (double) sourceHeight);

  NSDictionary<NSString *, id> *pixelBufferAttributes = @{
    (NSString *) kCVPixelBufferWidthKey : @(destinationWidth),
    (NSString *) kCVPixelBufferHeightKey : @(destinationHeight),
    (NSString *) kCVPixelBufferPixelFormatTypeKey : @(CVPixelBufferGetPixelFormatType(sourceBuffer)),
    (NSString *) kCVPixelBufferIOSurfacePropertiesKey : @{},
  };

  NSDictionary<NSString *, id> *pixelBufferPoolAttributes = @{
    (NSString *) kCVPixelBufferPoolMinimumBufferCountKey : @(4),
    (NSString *) kCVPixelBufferPoolAllocationThresholdKey : @(16),
  };

  CVPixelBufferPoolRef scaledPixelBufferPool;
  CVPixelBufferPoolCreate(nil, (__bridge CFDictionaryRef) pixelBufferPoolAttributes, (__bridge CFDictionaryRef) pixelBufferAttributes, &scaledPixelBufferPool);

  return scaledPixelBufferPool;
}

static CVPixelBufferPoolRef createNV12PixelBufferPool(size_t width, size_t height)
{
  NSDictionary<NSString *, id> *pixelBufferAttributes = @{
    (NSString *) kCVPixelBufferWidthKey : @(width),
    (NSString *) kCVPixelBufferHeightKey : @(height),
    (NSString *) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
    (NSString *) kCVPixelBufferIOSurfacePropertiesKey : @{},
  };

  NSDictionary<NSString *, id> *pixelBufferPoolAttributes = @{
    (NSString *) kCVPixelBufferPoolMinimumBufferCountKey : @(4),
    (NSString *) kCVPixelBufferPoolAllocationThresholdKey : @(16),
  };

  CVPixelBufferPoolRef pool;
  CVPixelBufferPoolCreate(nil, (__bridge CFDictionaryRef) pixelBufferPoolAttributes, (__bridge CFDictionaryRef) pixelBufferAttributes, &pool);
  return pool;
}

static NSDictionary<NSString *, id> *FBBitmapStreamPixelBufferAttributesFromPixelBuffer(CVPixelBufferRef pixelBuffer)
{
  size_t width = CVPixelBufferGetWidth(pixelBuffer);
  size_t height = CVPixelBufferGetHeight(pixelBuffer);
  size_t frameSize = CVPixelBufferGetDataSize(pixelBuffer);
  size_t rowSize = CVPixelBufferGetBytesPerRow(pixelBuffer);
  OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
  NSString *pixelFormatString = (__bridge_transfer NSString *) UTCreateStringForOSType(pixelFormat);

  size_t columnLeft;
  size_t columnRight;
  size_t rowsTop;
  size_t rowsBottom;

  CVPixelBufferGetExtendedPixels(pixelBuffer, &columnLeft, &columnRight, &rowsTop, &rowsBottom);
  return @{
    @"width" : @(width),
    @"height" : @(height),
    @"row_size" : @(rowSize),
    @"frame_size" : @(frameSize),
    @"padding_column_left" : @(columnLeft),
    @"padding_column_right" : @(columnRight),
    @"padding_row_top" : @(rowsTop),
    @"padding_row_bottom" : @(rowsBottom),
    @"format" : pixelFormatString,
  };
}

static void CompressedFrameCallback(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus encodeStatus, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer)
{
  (void)(__bridge_transfer FBVideoCompressorCallbackSourceFrame *)(sourceFrameRefCon);
  FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher = (__bridge FBSimulatorVideoStreamFramePusher_VideoToolbox *)(outputCallbackRefCon);
  [pusher handleCompressedSampleBuffer:sampleBuffer encodeStatus:encodeStatus infoFlags:infoFlags];
}

static void MJPEGCompressorCallback(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus encodeStats, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer)
{
  (void)(__bridge_transfer FBVideoCompressorCallbackSourceFrame *)(sourceFrameRefCon);
  FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher = (__bridge FBSimulatorVideoStreamFramePusher_VideoToolbox *)(outputCallbackRefCon);
  CMBlockBufferRef blockBufffer = CMSampleBufferGetDataBuffer(sampleBuffer);
  NSError *error = nil;
  if (!WriteJPEGDataToMJPEGStream(blockBufffer, pusher.consumer, pusher.logger, &error)) {
    [pusher.logger log:[NSString stringWithFormat:@"Failed to write MJPEG frame: %@", error]];
  }
}

static void MinicapCompressorCallback(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus encodeStats, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer)
{
  FBVideoCompressorCallbackSourceFrame *sourceFrame = (__bridge_transfer FBVideoCompressorCallbackSourceFrame *) sourceFrameRefCon;
  NSUInteger frameNumber = sourceFrame.frameNumber;
  FBSimulatorVideoStreamFramePusher_VideoToolbox *pusher = (__bridge FBSimulatorVideoStreamFramePusher_VideoToolbox *)(outputCallbackRefCon);
  if (frameNumber == 0) {
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
    NSError *error = nil;
    if (!WriteMinicapHeaderToStream((uint32) dimensions.width, (uint32) dimensions.height, pusher.consumer, pusher.logger, &error)) {
      [pusher.logger log:[NSString stringWithFormat:@"Failed to write Minicap header: %@", error]];
    }
  }
  CMBlockBufferRef blockBufffer = CMSampleBufferGetDataBuffer(sampleBuffer);
  NSError *error = nil;
  if (!WriteJPEGDataToMinicapStream(blockBufffer, pusher.consumer, pusher.logger, &error)) {
    [pusher.logger log:[NSString stringWithFormat:@"Failed to write Minicap frame: %@", error]];
  }
}

@implementation FBVideoCompressorCallbackSourceFrame

- (instancetype)initWithPixelBuffer:(CVPixelBufferRef)pixelBuffer frameNumber:(NSUInteger)frameNumber
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _pixelBuffer = pixelBuffer;
  _frameNumber = frameNumber;

  return self;
}

- (void)dealloc
{
  CVPixelBufferRelease(_pixelBuffer);
}

@end

@implementation FBSimulatorVideoStreamFramePusher_Bitmap

- (instancetype)initWithConsumer:(id<FBDataConsumer>)consumer scaleFactor:(NSNumber *)scaleFactor
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;
  _scaleFactor = scaleFactor;

  return self;
}

- (BOOL)setupWithPixelBuffer:(CVPixelBufferRef)pixelBuffer edgeInsets:(FBVideoStreamEdgeInsets)edgeInsets error:(NSError **)error
{
  if (self.scaleFactor && [self.scaleFactor isGreaterThan:@0] && [self.scaleFactor isLessThan:@1]) {
    self.scaledPixelBufferPoolRef = createScaledPixelBufferPool(pixelBuffer, self.scaleFactor);
    VTPixelTransferSessionRef transferSession;
    OSStatus status = VTPixelTransferSessionCreate(kCFAllocatorDefault, &transferSession);
    if (status != noErr) {
      return [[FBControlCoreError describe:[NSString stringWithFormat:@"Failed to create VTPixelTransferSession: %d", (int)status]] failBool:error];
    }
    self.pixelTransferSession = transferSession;
  }
  return YES;
}

- (BOOL)tearDown:(NSError **)error
{
  if (self.pixelTransferSession) {
    VTPixelTransferSessionInvalidate(self.pixelTransferSession);
    CFRelease(self.pixelTransferSession);
    self.pixelTransferSession = nil;
  }
  CVPixelBufferPoolRelease(self.scaledPixelBufferPoolRef);
  return YES;
}

- (BOOL)writeEncodedFrame:(CVPixelBufferRef)pixelBuffer frameNumber:(NSUInteger)frameNumber timeAtFirstFrame:(CFTimeInterval)timeAtFirstFrame frameDuration:(CFTimeInterval)frameDuration forceKeyFrame:(BOOL)forceKeyFrame error:(NSError **)error
{
  CVPixelBufferRef bufferToWrite = pixelBuffer;
  CVPixelBufferRef toFree = nil;
  CVPixelBufferPoolRef bufferPool = self.scaledPixelBufferPoolRef;
  if (bufferPool != nil && self.pixelTransferSession != nil) {
    CVPixelBufferRef resizedBuffer;
    if (kCVReturnSuccess == CVPixelBufferPoolCreatePixelBuffer(nil, bufferPool, &resizedBuffer)) {
      OSStatus status = VTPixelTransferSessionTransferImage(self.pixelTransferSession, pixelBuffer, resizedBuffer);
      if (status == noErr) {
        bufferToWrite = resizedBuffer;
        toFree = resizedBuffer;
      } else {
        CVPixelBufferRelease(resizedBuffer);
      }
    }
  }

  CVPixelBufferLockBaseAddress(bufferToWrite, kCVPixelBufferLock_ReadOnly);

  void *baseAddress = CVPixelBufferGetBaseAddress(bufferToWrite);
  size_t size = CVPixelBufferGetDataSize(bufferToWrite);

  if ([self.consumer conformsToProtocol:@protocol(FBDataConsumerSync)]) {
    NSData *data = [NSData dataWithBytesNoCopy:baseAddress length:size freeWhenDone:NO];
    [self.consumer consumeData:data];
  } else {
    NSData *data = [NSData dataWithBytes:baseAddress length:size];
    [self.consumer consumeData:data];
  }

  CVPixelBufferUnlockBaseAddress(bufferToWrite, kCVPixelBufferLock_ReadOnly);
  CVPixelBufferRelease(toFree);

  return YES;
}

@end

@implementation FBSimulatorVideoStreamFramePusher_VideoToolbox

- (instancetype)initWithConfiguration:(FBVideoStreamConfiguration *)configuration compressionSessionProperties:(NSDictionary<NSString *, id> *)compressionSessionProperties videoCodec:(CMVideoCodecType)videoCodec consumer:(id<FBDataConsumer>)consumer compressorCallback:(VTCompressionOutputCallback)compressorCallback frameWriter:(FBCompressedFrameWriter)frameWriter frameWriterContext:(id _Nullable)frameWriterContext logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _compressionSessionProperties = compressionSessionProperties;
  _compressorCallback = compressorCallback;
  _frameWriter = frameWriter;
  _frameWriterContext = frameWriterContext;
  _consumer = consumer;
  _logger = logger;
  _videoCodec = videoCodec;
  _statsTimer = FBPeriodicStatsTimerCreate(5.0);

  return self;
}

- (void)handleCompressedSampleBuffer:(CMSampleBufferRef)sampleBuffer
                        encodeStatus:(OSStatus)encodeStatus
                           infoFlags:(VTEncodeInfoFlags)infoFlags
{
  FBPeriodicStatsTimer timer = self.statsTimer;
  if (timer.startTime == 0) {
    // First call — initialize the timer.
    CFTimeInterval unused1, unused2;
    FBPeriodicStatsTimerTick(&timer, &unused1, &unused2);
    self.statsTimer = timer;
    [self.logger.info log:@"First encode callback received"];
  }

  [self _processCompressedSampleBuffer:sampleBuffer encodeStatus:encodeStatus infoFlags:infoFlags];

  CFTimeInterval intervalDuration, totalElapsed;
  timer = self.statsTimer;
  if (!FBPeriodicStatsTimerTick(&timer, &intervalDuration, &totalElapsed)) {
    return;
  }
  self.statsTimer = timer;

  FBVideoEncoderStats current = self.stats;
  FBVideoEncoderStats last = self.lastLoggedStats;
  NSUInteger intervalCallbacks = current.callbackCount - last.callbackCount;
  NSUInteger intervalWritten = current.writeCount - last.writeCount;
  NSUInteger intervalDropped = current.dropCount - last.dropCount;
  NSUInteger intervalWriteFailures = current.writeFailureCount - last.writeFailureCount;
  NSUInteger intervalEncodeErrors = current.encodeErrorCount - last.encodeErrorCount;
  NSUInteger intervalTornFrames = current.tornFrameCount - last.tornFrameCount;
  NSUInteger intervalEncodedBytes = current.totalEncodedBytes - last.totalEncodedBytes;
  CFTimeInterval intervalEncodeSubmitSeconds = current.totalEncodeSubmitSeconds - last.totalEncodeSubmitSeconds;
  self.lastLoggedStats = current;

  double totalFps = totalElapsed > 0 ? (double)current.callbackCount / totalElapsed : 0;
  double intervalFps = intervalDuration > 0 ? (double)intervalCallbacks / intervalDuration : 0;
  double intervalBitrateKbps = intervalDuration > 0 ? (double)intervalEncodedBytes * 8.0 / 1000.0 / intervalDuration : 0;
  double totalBitrateKbps = totalElapsed > 0 ? (double)current.totalEncodedBytes * 8.0 / 1000.0 / totalElapsed : 0;
  double intervalAvgEncodeMs = intervalCallbacks > 0 ? (intervalEncodeSubmitSeconds / (double)intervalCallbacks) * 1000.0 : 0;
  double totalAvgEncodeMs = current.callbackCount > 0 ? (current.totalEncodeSubmitSeconds / (double)current.callbackCount) * 1000.0 : 0;

  [self.logger.info log:[NSString stringWithFormat:
                         @"Video stats (interval): %lu callbacks in %.1fs (%.1f fps, %.0f kbps, %.2f ms/frame encode) — %lu written, %lu dropped, %lu write failures, %lu encode errors, %lu torn",
                         (unsigned long)intervalCallbacks,
                         intervalDuration,
                         intervalFps,
                         intervalBitrateKbps,
                         intervalAvgEncodeMs,
                         (unsigned long)intervalWritten,
                         (unsigned long)intervalDropped,
                         (unsigned long)intervalWriteFailures,
                         (unsigned long)intervalEncodeErrors,
                         (unsigned long)intervalTornFrames]];
  [self.logger.info log:[NSString stringWithFormat:
                         @"Video stats (total): %lu callbacks in %.1fs (%.1f fps, %.0f kbps, %.2f ms/frame encode) — %lu written, %lu dropped, %lu write failures, %lu encode errors, %lu torn",
                         (unsigned long)current.callbackCount,
                         totalElapsed,
                         totalFps,
                         totalBitrateKbps,
                         totalAvgEncodeMs,
                         (unsigned long)current.writeCount,
                         (unsigned long)current.dropCount,
                         (unsigned long)current.writeFailureCount,
                         (unsigned long)current.encodeErrorCount,
                         (unsigned long)current.tornFrameCount]];
}

- (void)_processCompressedSampleBuffer:(CMSampleBufferRef)sampleBuffer
                          encodeStatus:(OSStatus)encodeStatus
                             infoFlags:(VTEncodeInfoFlags)infoFlags
{
  FBVideoEncoderStats s = self.stats;
  s.callbackCount += 1;

  if (encodeStatus != noErr) {
    s.encodeErrorCount += 1;
    self.stats = s;
    [self.logger log:[NSString stringWithFormat:@"VideoToolbox encode error: OSStatus %d", (int)encodeStatus]];
    return;
  }

  BOOL frameDropped = (infoFlags & kVTEncodeInfo_FrameDropped) != 0;
  BOOL writeSucceeded = NO;
  if (!frameDropped) {
    NSError *error = nil;
    writeSucceeded = self.frameWriter(sampleBuffer, self.frameWriterContext, self.consumer, self.logger, &error);
    if (writeSucceeded) {
      CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
      if (dataBuffer) {
        s.totalEncodedBytes += CMBlockBufferGetDataLength(dataBuffer);
      }
    }
  }

  if (frameDropped || !writeSucceeded) {
    if (frameDropped) {
      s.dropCount += 1;
    } else {
      s.writeFailureCount += 1;
    }
    self.stats = s;
    self.consecutiveNotReadyFrameCount += 1;
    NSUInteger consecutiveFailures = self.consecutiveNotReadyFrameCount;

    if (!self.warmupComplete) {
      static const NSUInteger WarmupWindowFrames = 20;
      if (consecutiveFailures == WarmupWindowFrames) {
        [self.logger log:[NSString stringWithFormat:@"Encoder has not produced a frame after %lu attempts — bitrate may be too low for this resolution", (unsigned long)consecutiveFailures]];
        self.starvationWarningLogged = YES;
      }
    } else {
      static const NSUInteger StarvationThreshold = 10;
      if (consecutiveFailures == StarvationThreshold && !self.starvationWarningLogged) {
        [self.logger log:[NSString stringWithFormat:@"Encoder starvation: %lu consecutive frames not ready after warmup — bitrate is likely too low", (unsigned long)consecutiveFailures]];
        self.starvationWarningLogged = YES;
      }
    }
    return;
  }

  // Success
  s.writeCount += 1;
  self.stats = s;
  NSUInteger failuresBefore = self.consecutiveNotReadyFrameCount;
  self.consecutiveNotReadyFrameCount = 0;
  self.starvationWarningLogged = NO;

  if (!self.warmupComplete) {
    self.warmupComplete = YES;
    if (failuresBefore > 0) {
      [self.logger log:[NSString stringWithFormat:@"Encoder warmed up after %lu skipped frames", (unsigned long)failuresBefore]];
    }
  }
}

- (BOOL)setupWithPixelBuffer:(CVPixelBufferRef)pixelBuffer edgeInsets:(FBVideoStreamEdgeInsets)edgeInsets error:(NSError **)error
{
  NSDictionary<NSString *, id> *encoderSpecification = @{
    (NSString *) kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder : @YES,
  };

  if (@available(macOS 12.1, *)) {
    encoderSpecification = @{
      (NSString *) kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder : @YES,
      (NSString *) kVTVideoEncoderSpecification_EnableLowLatencyRateControl : @YES,
    };
  }
  size_t sourceWidth = CVPixelBufferGetWidth(pixelBuffer);
  size_t sourceHeight = CVPixelBufferGetHeight(pixelBuffer);
  size_t destinationWidth = sourceWidth;
  size_t destinationHeight = sourceHeight;
  NSNumber *scaleFactor = self.configuration.scaleFactor;
  if (scaleFactor && [scaleFactor isGreaterThan:@0] && [scaleFactor isLessThan:@1]) {
    destinationWidth = (size_t) floor(scaleFactor.doubleValue * (double)sourceWidth);
    destinationHeight = (size_t) floor(scaleFactor.doubleValue * (double)sourceHeight);
    [self.logger.info log:[NSString stringWithFormat:@"Applying %@ scale from w=%zu/h=%zu to w=%zu/h=%zu", scaleFactor, sourceWidth, sourceHeight, destinationWidth, destinationHeight]];
  }
  // Add edge insets to output dimensions. The composited frame includes the insets,
  // so the NV12 pool and compression session must accommodate the full output size.
  destinationWidth += edgeInsets.left + edgeInsets.right;
  destinationHeight += edgeInsets.top + edgeInsets.bottom;
  // H.264 and NV12 require even dimensions.
  destinationWidth += destinationWidth % 2;
  destinationHeight += destinationHeight % 2;

  // Always create a VTPixelTransferSession to convert BGRA→NV12 (and scale if needed).
  // VTCompressionSession's native input format is NV12 (420v). Feeding it BGRA causes
  // an internal conversion pass. By converting explicitly we let VT pre-allocate its
  // pipeline via sourceImageBufferAttributes and avoid the implicit conversion.
  VTPixelTransferSessionRef transferSession;
  OSStatus transferStatus = VTPixelTransferSessionCreate(kCFAllocatorDefault, &transferSession);
  if (transferStatus != noErr) {
    return [[FBSimulatorError describe:[NSString stringWithFormat:@"Failed to create VTPixelTransferSession: %d", (int)transferStatus]] failBool:error];
  }
  self.pixelTransferSession = transferSession;
  CVPixelBufferPoolRef nv12Pool = createNV12PixelBufferPool(destinationWidth, destinationHeight);
  self.nv12PixelBufferPoolRef = nv12Pool;
  [self.logger.info log:[NSString stringWithFormat:@"Created BGRA→NV12 conversion pipeline at w=%zu/h=%zu (GPU via VTPixelTransferSession)", destinationWidth, destinationHeight]];

  // Tell VTCompressionSession that it will receive NV12 IOSurface-backed buffers.
  NSDictionary<NSString *, id> *sourceImageBufferAttributes = @{
    (NSString *) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
    (NSString *) kCVPixelBufferWidthKey : @(destinationWidth),
    (NSString *) kCVPixelBufferHeightKey : @(destinationHeight),
    (NSString *) kCVPixelBufferIOSurfacePropertiesKey : @{},
  };

  VTCompressionSessionRef compressionSession = NULL;
  OSStatus status = VTCompressionSessionCreate(
    nil, // Allocator
    (int32_t) destinationWidth,
    (int32_t) destinationHeight,
    self.videoCodec,
    (__bridge CFDictionaryRef) encoderSpecification,
    (__bridge CFDictionaryRef) sourceImageBufferAttributes,
    nil, // Compressed Data Allocator
    self.compressorCallback,
    (__bridge void * _Nullable)(self), // Callback Ref.
    &compressionSession
  );
  if (status != noErr) {
    return [[FBSimulatorError
             describe:[NSString stringWithFormat:@"Failed to start Compression Session %d", status]]
            failBool:error];
  }

  status = VTSessionSetProperties(
    compressionSession,
    (__bridge CFDictionaryRef) self.compressionSessionProperties
  );
  if (status != noErr) {
    return [[FBSimulatorError
             describe:[NSString stringWithFormat:@"Failed to set compression session properties %d", status]]
            failBool:error];
  }
  status = VTCompressionSessionPrepareToEncodeFrames(compressionSession);
  if (status != noErr) {
    return [[FBSimulatorError
             describe:[NSString stringWithFormat:@"Failed to prepare compression session %d", status]]
            failBool:error];
  }
  self.compressionSession = compressionSession;
  return YES;
}

- (BOOL)tearDown:(NSError **)error
{
  VTCompressionSessionRef compression = self.compressionSession;
  if (compression) {
    VTCompressionSessionCompleteFrames(compression, kCMTimeInvalid);
    VTCompressionSessionInvalidate(compression);
    self.compressionSession = nil;
  }
  if (self.pixelTransferSession) {
    VTPixelTransferSessionInvalidate(self.pixelTransferSession);
    CFRelease(self.pixelTransferSession);
    self.pixelTransferSession = nil;
  }
  CVPixelBufferPoolRelease(self.scaledPixelBufferPoolRef);
  CVPixelBufferPoolRelease(self.nv12PixelBufferPoolRef);
  return YES;
}

- (BOOL)writeEncodedFrame:(CVPixelBufferRef)pixelBuffer frameNumber:(NSUInteger)frameNumber timeAtFirstFrame:(CFTimeInterval)timeAtFirstFrame frameDuration:(CFTimeInterval)frameDuration forceKeyFrame:(BOOL)forceKeyFrame error:(NSError **)error
{
  VTCompressionSessionRef compressionSession = self.compressionSession;
  if (!compressionSession) {
    return [[FBControlCoreError
             describe:@"No compression session"]
            failBool:error];
  }

  CVPixelBufferRef bufferToWrite = pixelBuffer;
  FBVideoCompressorCallbackSourceFrame *sourceFrameRef = [[FBVideoCompressorCallbackSourceFrame alloc] initWithPixelBuffer:nil frameNumber:frameNumber];

  CFAbsoluteTime encodeStart = CFAbsoluteTimeGetCurrent();

  // Convert BGRA→NV12 (and scale if needed) in a single VTPixelTransferSession call.
  // VTCompressionSession's native input format is NV12; feeding it NV12 directly
  // avoids an internal conversion pass. When scaleFactor is set, the NV12 pool is
  // already sized to the destination dimensions, so scaling + format conversion
  // happen in one GPU pass.
  CVPixelBufferPoolRef nv12Pool = self.nv12PixelBufferPoolRef;
  if (nv12Pool != nil && self.pixelTransferSession != nil) {
    CVPixelBufferRef nv12Buffer;
    CVReturn returnStatus = CVPixelBufferPoolCreatePixelBuffer(nil, nv12Pool, &nv12Buffer);
    if (returnStatus == kCVReturnSuccess) {
      OSStatus transferStatus = VTPixelTransferSessionTransferImage(self.pixelTransferSession, pixelBuffer, nv12Buffer);
      if (transferStatus == noErr) {
        bufferToWrite = nv12Buffer;
        sourceFrameRef.pixelBuffer = nv12Buffer;
      } else {
        [self.logger log:[NSString stringWithFormat:@"VTPixelTransferSession BGRA→NV12 failed: %d — falling back to BGRA input", (int)transferStatus]];
        CVPixelBufferRelease(nv12Buffer);
      }
    } else {
      [self.logger log:[NSString stringWithFormat:@"Failed to get a pixel buffer from the NV12 pool: %d", returnStatus]];
    }
  }

  VTEncodeInfoFlags flags;
  CMTime time = CMTimeMakeWithSeconds(CFAbsoluteTimeGetCurrent() - timeAtFirstFrame, NSEC_PER_SEC);
  CMTime duration = frameDuration > 0 ? CMTimeMakeWithSeconds(frameDuration, NSEC_PER_SEC) : kCMTimeInvalid;
  NSDictionary *frameProperties = nil;
  if (frameNumber == 0 || forceKeyFrame) {
    frameProperties = @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame : @YES};
  }
  // Lock the source buffer for read-only access during the encode call. For
  // IOSurface-backed buffers this prevents the simulator from writing while
  // VTCompressionSession reads the pixel data, avoiding screen tearing.
  // VTCompressionSessionEncodeFrame captures the pixel data before returning
  // so we can unlock immediately after.
  //
  // Check the IOSurface seed before and after to detect if the surface was
  // modified during the encode (which would indicate a torn frame despite
  // the advisory lock).
  IOSurfaceRef surface = CVPixelBufferGetIOSurface(bufferToWrite);
  uint32_t seedBefore = surface ? IOSurfaceGetSeed(surface) : 0;
  CVPixelBufferLockBaseAddress(bufferToWrite, kCVPixelBufferLock_ReadOnly);
  OSStatus status = VTCompressionSessionEncodeFrame(
    compressionSession,
    bufferToWrite,
    time,
    duration,
    (__bridge CFDictionaryRef)frameProperties,  // Frame properties
    (__bridge_retained void * _Nullable)(sourceFrameRef),
    &flags
  );
  CVPixelBufferUnlockBaseAddress(bufferToWrite, kCVPixelBufferLock_ReadOnly);

  // Track time spent in NV12 conversion + encode submission.
  {
    CFAbsoluteTime encodeEnd = CFAbsoluteTimeGetCurrent();
    FBVideoEncoderStats s = self.stats;
    s.totalEncodeSubmitSeconds += (encodeEnd - encodeStart);
    self.stats = s;
  }

  if (surface) {
    uint32_t seedAfter = IOSurfaceGetSeed(surface);
    if (seedAfter != seedBefore) {
      FBVideoEncoderStats s = self.stats;
      s.tornFrameCount += 1;
      self.stats = s;
    }
  }
  if (status != 0) {
    return [[FBControlCoreError
             describe:[NSString stringWithFormat:@"Failed to compress %d", status]]
            failBool:error];
  }
  return YES;
}

- (FBVideoEncoderStats)currentStats
{
  return self.stats;
}

@end

@interface FBSimulatorVideoStream_Lazy : FBSimulatorVideoStream

@end

@interface FBSimulatorVideoStream_Eager : FBSimulatorVideoStream

@property (nonatomic, readonly, assign) NSUInteger framesPerSecond;
@property (nonatomic, readwrite, strong) NSThread *framePusherThread;

- (instancetype)initWithFramebuffer:(FBFramebuffer *)framebuffer configuration:(FBVideoStreamConfiguration *)configuration framesPerSecond:(NSUInteger)framesPerSecond edgeInsets:(FBVideoStreamEdgeInsets)edgeInsets writeQueue:(dispatch_queue_t)writeQueue logger:(id<FBControlCoreLogger>)logger;

@end

@interface FBSimulatorVideoStream ()

@property (nonatomic, readonly, strong) FBFramebuffer *framebuffer;
@property (nonatomic, readonly, copy) FBVideoStreamConfiguration *configuration;
@property (nonatomic, readonly, assign) FBVideoStreamEdgeInsets edgeInsets;
@property (nonatomic, readonly, strong) dispatch_queue_t writeQueue;
@property (nonatomic, readonly, strong) id<FBControlCoreLogger> logger;
@property (nonatomic, readonly, strong) FBMutableFuture<NSNull *> *startedFuture;
@property (nonatomic, readonly, strong) FBMutableFuture<NSNull *> *stoppedFuture;

@property (nullable, nonatomic, readwrite, assign) CVPixelBufferRef pixelBuffer;
@property (nonatomic, readwrite, assign) CFTimeInterval timeAtFirstFrame;
@property (nonatomic, readwrite, assign) CFTimeInterval timeAtLastPush;
@property (nonatomic, readwrite, assign) NSUInteger frameNumber;
@property (nullable, nonatomic, readwrite, copy) NSDictionary<NSString *, id> *pixelBufferAttributes;
@property (nullable, nonatomic, readwrite, strong) id<FBDataConsumer> consumer;
@property (nullable, nonatomic, readwrite, strong) id<FBSimulatorVideoStreamFramePusher> framePusher;
@property (nullable, nonatomic, readwrite, strong) id frameWriterContext;

// Overlay compositing
@property (nullable, nonatomic, readwrite, assign) CVPixelBufferRef overlayBuffer;
@property (nullable, nonatomic, readwrite, strong) CIContext *compositorCIContext;
@property (nullable, nonatomic, readwrite, assign) CVPixelBufferPoolRef compositedBufferPool;
@property (nonatomic, readwrite, assign) size_t compositedWidth;
@property (nonatomic, readwrite, assign) size_t compositedHeight;

- (void)pushFrameForceKeyFrame:(BOOL)forceKeyFrame;
- (nullable CIImage *)compositedImageFromSource:(CVPixelBufferRef)sourceBuffer;

@end

@implementation FBSimulatorVideoStream

+ (dispatch_queue_t)writeQueue
{
  return dispatch_queue_create("com.facebook.FBSimulatorControl.BitmapStream", DISPATCH_QUEUE_SERIAL);
}

+ (instancetype)streamWithFramebuffer:(FBFramebuffer *)framebuffer configuration:(FBVideoStreamConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  FBVideoStreamEdgeInsets zeroInsets = {0, 0, 0, 0};
  return [self streamWithFramebuffer:framebuffer configuration:configuration edgeInsets:zeroInsets logger:logger];
}

+ (instancetype)streamWithFramebuffer:(FBFramebuffer *)framebuffer configuration:(FBVideoStreamConfiguration *)configuration edgeInsets:(FBVideoStreamEdgeInsets)edgeInsets logger:(id<FBControlCoreLogger>)logger
{
  NSNumber *framesPerSecondNumber = configuration.framesPerSecond;
  NSUInteger framesPerSecond = framesPerSecondNumber.unsignedIntegerValue;
  if (framesPerSecondNumber && framesPerSecond > 0) {
    return [[FBSimulatorVideoStream_Eager alloc] initWithFramebuffer:framebuffer
                                                       configuration:configuration
                                                     framesPerSecond:framesPerSecond
                                                          edgeInsets:edgeInsets
                                                          writeQueue:self.writeQueue
                                                              logger:logger];
  }
  return [[FBSimulatorVideoStream_Lazy alloc] initWithFramebuffer:framebuffer configuration:configuration edgeInsets:edgeInsets writeQueue:self.writeQueue logger:logger];
}

- (instancetype)initWithFramebuffer:(FBFramebuffer *)framebuffer configuration:(FBVideoStreamConfiguration *)configuration edgeInsets:(FBVideoStreamEdgeInsets)edgeInsets writeQueue:(dispatch_queue_t)writeQueue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _framebuffer = framebuffer;
  _configuration = configuration;
  _edgeInsets = edgeInsets;
  _writeQueue = writeQueue;
  _logger = logger;
  _startedFuture = FBMutableFuture.future;
  _stoppedFuture = FBMutableFuture.future;

  return self;
}

#pragma mark Public

- (FBFuture<NSNull *> *)startStreaming:(id<FBDataConsumer>)consumer
{
  return [[FBFuture
           onQueue:self.writeQueue
           resolve:^FBFuture<NSNull *> * {
             if (self.startedFuture.hasCompleted) {
               return [[FBSimulatorError
                        describe:@"Cannot start streaming, since streaming is stopped"]
                       failFuture];
             }
             if (self.consumer) {
               return [[FBSimulatorError
                        describe:@"Cannot start streaming, since streaming has already has started"]
                       failFuture];
             }
             self.consumer = consumer;
             return [self attachConsumerIfNeeded];
           }]
          onQueue:self.writeQueue
          fmap:^(id _) {
            return self.startedFuture;
          }];
}

- (FBFuture<NSNull *> *)stopStreaming
{
  return [FBFuture
          onQueue:self.writeQueue
          resolve:^FBFuture<NSNull *> *{
            if (self.stoppedFuture.hasCompleted) {
              return self.stoppedFuture;
            }
            id<FBDataConsumer> consumer = self.consumer;
            if (!consumer) {
              return [[FBSimulatorError
                       describe:@"Cannot stop streaming, no consumer attached"]
                      failFuture];
            }
            if (![self.framebuffer isConsumerAttached:self]) {
              return [[FBSimulatorError
                       describe:@"Cannot stop streaming, is not attached to a surface"]
                      failFuture];
            }
            self.consumer = nil;
            [self.framebuffer detachConsumer:self];
            [consumer consumeEndOfFile];
            if (self.framePusher) {
              NSError *error = nil;
              if (![self.framePusher tearDown:&error]) {
                return [[FBSimulatorError
                         describe:[NSString stringWithFormat:@"Failed to tear down frame pusher: %@", error]]
                        failFuture];
              }
            }
            self.frameWriterContext = nil;
            // Clean up overlay compositing resources.
            self.overlayBuffer = NULL;
            if (self.compositedBufferPool) {
              CVPixelBufferPoolRelease(self.compositedBufferPool);
              self.compositedBufferPool = NULL;
            }
            [self.stoppedFuture resolveWithResult:NSNull.null];
            return self.stoppedFuture;
          }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)attachConsumerIfNeeded
{
  return [FBFuture
          onQueue:self.writeQueue
          resolve:^{
            if ([self.framebuffer isConsumerAttached:self]) {
              [self.logger log:[NSString stringWithFormat:@"Already attached %@ as a consumer", self]];
              return FBFuture.empty;
            }
            // If we have a surface now, we can start rendering, so mount the surface.
            IOSurface *surface = [self.framebuffer attachConsumer:self onQueue:self.writeQueue];
            [self didChangeIOSurface:surface];
            return FBFuture.empty;
          }];
}

#pragma mark FBFramebufferConsumer

- (void)didChangeIOSurface:(IOSurface *)surface
{
  [self mountSurface:surface error:nil];
  [self pushFrameForceKeyFrame:NO];
}

- (void)didReceiveDamageRect
{}

#pragma mark Private

- (BOOL)mountSurface:(IOSurface *)surface error:(NSError **)error
{
  // Remove the old pixel buffer.
  CVPixelBufferRef oldBuffer = self.pixelBuffer;
  if (oldBuffer) {
    CVPixelBufferRelease(oldBuffer);
  }
  // Make a Buffer from the Surface
  CVPixelBufferRef buffer = NULL;
  CVReturn status = CVPixelBufferCreateWithIOSurface(
    NULL,
    (__bridge IOSurfaceRef _Nonnull)(surface),
    NULL,
    &buffer
  );
  if (status != kCVReturnSuccess) {
    return [[FBSimulatorError
             describe:[NSString stringWithFormat:@"Failed to create Pixel Buffer from Surface with errorCode %d", status]]
            failBool:error];
  }

  id<FBDataConsumer> consumer = self.consumer;
  if (!consumer) {
    return [[FBSimulatorError
             describe:@"Cannot mount surface when there is no consumer"]
            failBool:error];
  }

  // Get the Attributes
  NSDictionary<NSString *, id> *attributes = FBBitmapStreamPixelBufferAttributesFromPixelBuffer(buffer);
  [self.logger log:[NSString stringWithFormat:@"Mounting Surface with Attributes: %@", [FBCollectionInformation oneLineDescriptionFromDictionary:attributes]]];

  // Swap the pixel buffers.
  self.pixelBuffer = buffer;
  self.pixelBufferAttributes = attributes;

  id<FBSimulatorVideoStreamFramePusher> framePusher = [self.class framePusherForConfiguration:self.configuration
                                                                 compressionSessionProperties:self.compressionSessionProperties
                                                                                     consumer:consumer
                                                                                       logger:self.logger
                                                                                        error:nil];
  if (!framePusher) {
    return NO;
  }
  if (![framePusher setupWithPixelBuffer:buffer edgeInsets:self.edgeInsets error:error]) {
    return NO;
  }
  self.framePusher = framePusher;
  if ([framePusher isKindOfClass:[FBSimulatorVideoStreamFramePusher_VideoToolbox class]]) {
    self.frameWriterContext = ((FBSimulatorVideoStreamFramePusher_VideoToolbox *)framePusher).frameWriterContext;
  }

  // Set up overlay compositing infrastructure.
  // Metal-backed CIContext for GPU compositing — created once, reused across frames.
  if (!self.compositorCIContext) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device) {
      self.compositorCIContext = [CIContext contextWithMTLDevice:device options:@{kCIContextCacheIntermediates : @NO}];
    } else {
      self.compositorCIContext = [CIContext contextWithOptions:@{kCIContextCacheIntermediates : @NO}];
    }
  }
  // IOSurface-backed BGRA pixel buffer pool for composited output.
  // Include edge insets in the pool dimensions so the composited frame has room for overlay content.
  if (self.compositedBufferPool) {
    CVPixelBufferPoolRelease(self.compositedBufferPool);
    self.compositedBufferPool = NULL;
  }
  size_t width = CVPixelBufferGetWidth(buffer);
  size_t height = CVPixelBufferGetHeight(buffer);
  NSNumber *scaleFactor = self.configuration.scaleFactor;
  size_t compositedWidth = width;
  size_t compositedHeight = height;
  if (scaleFactor && [scaleFactor isGreaterThan:@0] && [scaleFactor isLessThan:@1]) {
    compositedWidth = (size_t) floor(scaleFactor.doubleValue * (double)width);
    compositedHeight = (size_t) floor(scaleFactor.doubleValue * (double)height);
  }
  FBVideoStreamEdgeInsets insets = self.edgeInsets;
  compositedWidth += insets.left + insets.right;
  compositedHeight += insets.top + insets.bottom;
  // H.264 and NV12 require even dimensions.
  compositedWidth += compositedWidth % 2;
  compositedHeight += compositedHeight % 2;
  self.compositedWidth = compositedWidth;
  self.compositedHeight = compositedHeight;
  NSDictionary *compositedPoolAttrs = @{
    (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
    (NSString *)kCVPixelBufferWidthKey : @(compositedWidth),
    (NSString *)kCVPixelBufferHeightKey : @(compositedHeight),
    (NSString *)kCVPixelBufferIOSurfacePropertiesKey : @{},
  };
  CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef)compositedPoolAttrs, &_compositedBufferPool);
  if (insets.top + insets.bottom + insets.left + insets.right > 0) {
    [self.logger.info log:[NSString stringWithFormat:@"Composited pool includes edge insets (t=%lu b=%lu l=%lu r=%lu): w=%zu/h=%zu", (unsigned long)insets.top, (unsigned long)insets.bottom, (unsigned long)insets.left, (unsigned long)insets.right, compositedWidth, compositedHeight]];
  }

  // Signal that we've started
  [self.startedFuture resolveWithResult:NSNull.null];

  return YES;
}

/// Build a composited CIImage from the source pixel buffer, applying edge insets
/// and overlaying the overlay buffer if present. Returns nil if no compositing is needed.
- (nullable CIImage *)compositedImageFromSource:(CVPixelBufferRef)sourceBuffer
{
  CVPixelBufferRef overlayBuf = self.overlayBuffer;
  FBVideoStreamEdgeInsets insets = self.edgeInsets;
  BOOL hasInsets = (insets.top + insets.bottom + insets.left + insets.right) > 0;
  BOOL needsComposite = hasInsets || (overlayBuf != NULL);
  if (!needsComposite || !self.compositorCIContext || !self.compositedBufferPool) {
    return nil;
  }

  CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:sourceBuffer];

  // Scale source to fit within the composited output (excluding insets).
  // CIImage origin is bottom-left, so after scaling we translate by (left, bottom)
  // to position the video content inside the inset frame.
  size_t sourceW = CVPixelBufferGetWidth(sourceBuffer);
  size_t targetW = self.compositedWidth - insets.left - insets.right;
  if (targetW != sourceW && sourceW > 0) {
    CGFloat s = (CGFloat)targetW / (CGFloat)sourceW;
    sourceImage = [sourceImage imageByApplyingTransform:CGAffineTransformMakeScale(s, s)];
  }
  if (insets.left > 0 || insets.bottom > 0) {
    sourceImage = [sourceImage imageByApplyingTransform:CGAffineTransformMakeTranslation(insets.left, insets.bottom)];
  }

  CIImage *result = sourceImage;
  if (overlayBuf) {
    CIImage *overlayImage = [CIImage imageWithCVPixelBuffer:overlayBuf];
    result = [overlayImage imageByCompositingOverImage:sourceImage];
  }
  return result;
}

- (void)pushFrameForceKeyFrame:(BOOL)forceKeyFrame
{
  // Ensure that we have all preconditions in place before pushing.
  CVPixelBufferRef pixelBufer = self.pixelBuffer;
  id<FBDataConsumer> consumer = self.consumer;
  id<FBSimulatorVideoStreamFramePusher> framePusher = self.framePusher;
  if (!pixelBufer || !consumer || !framePusher) {
    return;
  }
  if (!checkConsumerBufferLimit(consumer, self.logger)) {
    return;
  }

  CFTimeInterval now = CFAbsoluteTimeGetCurrent();
  NSUInteger frameNumber = self.frameNumber;
  if (frameNumber == 0) {
    self.timeAtFirstFrame = now;
  }
  CFTimeInterval timeAtFirstFrame = self.timeAtFirstFrame;
  CFTimeInterval frameDuration = self.timeAtLastPush > 0 ? (now - self.timeAtLastPush) : 0;
  self.timeAtLastPush = now;

  // Composite the overlay buffer over the source frame, or apply edge inset padding.
  // When any edge inset > 0, every frame must be composited to match the output dimensions
  // of the encoder (which includes the insets). Without this, raw framebuffer pixels
  // would be fed to an encoder sized for the larger output, causing distortion.
  CVPixelBufferRef bufferToEncode = pixelBufer;
  CVPixelBufferRef compositedBuffer = NULL;
  CIImage *composited = [self compositedImageFromSource:pixelBufer];
  if (composited) {
    CVReturn poolStatus = CVPixelBufferPoolCreatePixelBuffer(NULL, self.compositedBufferPool, &compositedBuffer);
    if (poolStatus == kCVReturnSuccess && compositedBuffer) {
      [self.compositorCIContext render:composited toCVPixelBuffer:compositedBuffer];
      bufferToEncode = compositedBuffer;
    }
  }

  // Push the Frame
  [framePusher writeEncodedFrame:bufferToEncode frameNumber:frameNumber timeAtFirstFrame:timeAtFirstFrame frameDuration:frameDuration forceKeyFrame:forceKeyFrame error:nil];

  // Release the composited buffer if we created one.
  if (compositedBuffer) {
    CVPixelBufferRelease(compositedBuffer);
  }

  // Increment frame counter
  self.frameNumber = frameNumber + 1;
}

+ (NSDictionary<NSString *, id> *)compressionSessionPropertiesForConfiguration:(FBVideoStreamConfiguration *)configuration callerProperties:(NSDictionary<NSString *, id> *)callerProperties
{
  NSMutableDictionary<NSString *, id> *derivedCompressionSessionProperties = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                (NSString *) kVTCompressionPropertyKey_RealTime : @YES,
                                                                                (NSString *) kVTCompressionPropertyKey_AllowFrameReordering : @NO,
                                                                                (NSString *) kVTCompressionPropertyKey_MaxFrameDelayCount : @0,
                                                                              }];

  if (configuration.rateControl.mode == FBVideoStreamRateControlModeAverageBitrate) {
    // Explicit bitrate: AverageBitRate is in bits/sec
    derivedCompressionSessionProperties[(NSString *) kVTCompressionPropertyKey_AverageBitRate] = configuration.rateControl.value;
  } else {
    // Constant-quality mode
    derivedCompressionSessionProperties[(NSString *) kVTCompressionPropertyKey_Quality] = configuration.rateControl.value;
  }

  [derivedCompressionSessionProperties addEntriesFromDictionary:callerProperties];
  derivedCompressionSessionProperties[(NSString *)kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration] = configuration.keyFrameRate;
  FBVideoStreamFormat *format = configuration.format;
  if (format.type == FBVideoStreamFormatTypeCompressedVideo
      && [format.codec isEqualToString:FBVideoStreamCodecH264]) {
    derivedCompressionSessionProperties[(NSString *) kVTCompressionPropertyKey_ProfileLevel] = (NSString *)kVTProfileLevel_H264_Baseline_AutoLevel;
    derivedCompressionSessionProperties[(NSString *) kVTCompressionPropertyKey_H264EntropyMode] = (NSString *)kVTH264EntropyMode_CAVLC;
    if (@available(macOS 12.1, *)) {
      derivedCompressionSessionProperties[(NSString *) kVTCompressionPropertyKey_ProfileLevel] = (NSString *)kVTProfileLevel_H264_High_AutoLevel;
      derivedCompressionSessionProperties[(NSString *) kVTCompressionPropertyKey_H264EntropyMode] = (NSString *)kVTH264EntropyMode_CABAC;
    }
  }
  if (format.type == FBVideoStreamFormatTypeCompressedVideo
      && [format.codec isEqualToString:FBVideoStreamCodecHEVC]) {
    derivedCompressionSessionProperties[(NSString *) kVTCompressionPropertyKey_AllowOpenGOP] = @NO;
    derivedCompressionSessionProperties[(NSString *) kVTCompressionPropertyKey_ProfileLevel] = (NSString *)kVTProfileLevel_HEVC_Main_AutoLevel;
    if (@available(macOS 13.0, *)) {
      derivedCompressionSessionProperties[(NSString *) kVTCompressionPropertyKey_ProfileLevel] = (NSString *)kVTProfileLevel_HEVC_Main10_AutoLevel;
    }
  }
  return [derivedCompressionSessionProperties copy];
}

+ (id<FBSimulatorVideoStreamFramePusher>)framePusherForConfiguration:(FBVideoStreamConfiguration *)configuration compressionSessionProperties:(NSDictionary<NSString *, id> *)compressionSessionProperties consumer:(id<FBDataConsumer>)consumer logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSDictionary<NSString *, id> *derivedCompressionSessionProperties = [self compressionSessionPropertiesForConfiguration:configuration callerProperties:compressionSessionProperties];
  FBVideoStreamFormat *format = configuration.format;
  switch (format.type) {
    case FBVideoStreamFormatTypeCompressedVideo: {
      if ([format.codec isEqualToString:FBVideoStreamCodecH264]) {
        if ([format.transport isEqualToString:FBVideoStreamTransportFMP4]) {
          FBFMP4MuxerContext *ctx = [[FBFMP4MuxerContext alloc] initWithHEVC:NO];
          return [[FBSimulatorVideoStreamFramePusher_VideoToolbox alloc]
                  initWithConfiguration:configuration
                  compressionSessionProperties:derivedCompressionSessionProperties
                  videoCodec:kCMVideoCodecType_H264
                  consumer:consumer
                  compressorCallback:CompressedFrameCallback
                  frameWriter:WriteH264FrameToFMP4Stream
                  frameWriterContext:ctx
                  logger:logger];
        }
        if ([format.transport isEqualToString:FBVideoStreamTransportMPEGTS]) {
          return [[FBSimulatorVideoStreamFramePusher_VideoToolbox alloc]
                  initWithConfiguration:configuration
                  compressionSessionProperties:derivedCompressionSessionProperties
                  videoCodec:kCMVideoCodecType_H264
                  consumer:consumer
                  compressorCallback:CompressedFrameCallback
                  frameWriter:WriteH264FrameToMPEGTSStream
                  frameWriterContext:nil
                  logger:logger];
        }
        return [[FBSimulatorVideoStreamFramePusher_VideoToolbox alloc]
                initWithConfiguration:configuration
                compressionSessionProperties:derivedCompressionSessionProperties
                videoCodec:kCMVideoCodecType_H264
                consumer:consumer
                compressorCallback:CompressedFrameCallback
                frameWriter:WriteFrameToAnnexBStream
                frameWriterContext:nil
                logger:logger];
      }
      if ([format.codec isEqualToString:FBVideoStreamCodecHEVC]) {
        if ([format.transport isEqualToString:FBVideoStreamTransportFMP4]) {
          FBFMP4MuxerContext *ctx = [[FBFMP4MuxerContext alloc] initWithHEVC:YES];
          return [[FBSimulatorVideoStreamFramePusher_VideoToolbox alloc]
                  initWithConfiguration:configuration
                  compressionSessionProperties:derivedCompressionSessionProperties
                  videoCodec:kCMVideoCodecType_HEVC
                  consumer:consumer
                  compressorCallback:CompressedFrameCallback
                  frameWriter:WriteHEVCFrameToFMP4Stream
                  frameWriterContext:ctx
                  logger:logger];
        }
        if ([format.transport isEqualToString:FBVideoStreamTransportMPEGTS]) {
          return [[FBSimulatorVideoStreamFramePusher_VideoToolbox alloc]
                  initWithConfiguration:configuration
                  compressionSessionProperties:derivedCompressionSessionProperties
                  videoCodec:kCMVideoCodecType_HEVC
                  consumer:consumer
                  compressorCallback:CompressedFrameCallback
                  frameWriter:WriteHEVCFrameToMPEGTSStream
                  frameWriterContext:nil
                  logger:logger];
        }
        return [[FBSimulatorVideoStreamFramePusher_VideoToolbox alloc]
                initWithConfiguration:configuration
                compressionSessionProperties:derivedCompressionSessionProperties
                videoCodec:kCMVideoCodecType_HEVC
                consumer:consumer
                compressorCallback:CompressedFrameCallback
                frameWriter:WriteHEVCFrameToAnnexBStream
                frameWriterContext:nil
                logger:logger];
      }
      return [[FBControlCoreError
               describe:[NSString stringWithFormat:@"Unsupported codec '%@'", format.codec]]
              fail:error];
    }
    case FBVideoStreamFormatTypeMJPEG:
      return [[FBSimulatorVideoStreamFramePusher_VideoToolbox alloc]
              initWithConfiguration:configuration
              compressionSessionProperties:derivedCompressionSessionProperties
              videoCodec:kCMVideoCodecType_JPEG
              consumer:consumer
              compressorCallback:MJPEGCompressorCallback
              frameWriter:NULL
              frameWriterContext:nil
              logger:logger];
    case FBVideoStreamFormatTypeMinicap:
      return [[FBSimulatorVideoStreamFramePusher_VideoToolbox alloc]
              initWithConfiguration:configuration
              compressionSessionProperties:derivedCompressionSessionProperties
              videoCodec:kCMVideoCodecType_JPEG
              consumer:consumer
              compressorCallback:MinicapCompressorCallback
              frameWriter:NULL
              frameWriterContext:nil
              logger:logger];
    case FBVideoStreamFormatTypeBGRA:
      return [[FBSimulatorVideoStreamFramePusher_Bitmap alloc] initWithConsumer:consumer scaleFactor:configuration.scaleFactor];
    default:
      return [[FBControlCoreError
               describe:[NSString stringWithFormat:@"Unsupported format type %lu", (unsigned long)format.type]]
              fail:error];
  }
}

- (NSDictionary<NSString *, id> *)compressionSessionProperties
{
  return @{};
}

#pragma mark Timed Metadata

- (void)writeTimedMetadata:(NSString *)text
{
  FBVideoStreamFormat *format = self.configuration.format;
  if (format.type != FBVideoStreamFormatTypeCompressedVideo) {
    return;
  }

  if ([format.transport isEqualToString:FBVideoStreamTransportMPEGTS]) {
    FBMPEGTSEnableMetadataStream();
    FBMPEGTSWriteTimedMetadata(text, self.consumer);
  } else if ([format.transport isEqualToString:FBVideoStreamTransportFMP4]) {
    FBFMP4MuxerContext *ctx = self.frameWriterContext;
    if (ctx) {
      FBFMP4WriteEmsgBox(ctx, text, self.consumer);
    }
  } else {
    [self.logger log:[NSString stringWithFormat:@"writeTimedMetadata: not supported for transport '%@', dropping", format.transport]];
  }
}

#pragma mark Overlay

- (void)updateOverlayBuffer:(nullable CVPixelBufferRef)overlayBuffer
{
  BOOL sameReference = (overlayBuffer == self.overlayBuffer);

  // Skip atomic self-assignment when the caller is updating buffer contents in-place.
  if (!sameReference) {
    self.overlayBuffer = overlayBuffer;
  }

  [self.logger log:[NSString stringWithFormat:@"Overlay %s (buffer=%p, frame=%lu)",
                    overlayBuffer
                    ? (sameReference ? "contents updated" : "buffer swapped")
                    : "cleared",
                    overlayBuffer, (unsigned long)self.frameNumber]];

  // In lazy/VFR mode: force a keyframe push so overlay changes are immediately
  // decodable by consumers (e.g. ffplay) that need a keyframe to start rendering.
  // In eager/CFR mode: the push loop runs at fixed cadence and picks up the change
  // on the next tick — an extra push would disrupt frame timing.
  if ([self isKindOfClass:[FBSimulatorVideoStream_Lazy class]]) {
    dispatch_async(self.writeQueue, ^{
      [self pushFrameForceKeyFrame:YES];
    });
  }
}

#pragma mark Screenshot

- (nullable NSData *)captureCompositedScreenshotWithError:(NSError **)error
{
  CVPixelBufferRef sourceBuffer = self.pixelBuffer;
  if (!sourceBuffer) {
    return [[FBSimulatorError describe:@"No pixel buffer available for screenshot"] fail:error];
  }

  // Build a CIImage, compositing the overlay if present, or applying edge inset padding.
  // Unlike pushFrameForceKeyFrame: (which needs a CVPixelBuffer for the encoder),
  // the screenshot path only needs a CGImage, so we skip the intermediate buffer
  // and go directly from the composited CIImage to createCGImage:.
  CIImage *ciImage = [self compositedImageFromSource:sourceBuffer];
  if (!ciImage) {
    ciImage = [CIImage imageWithCVPixelBuffer:sourceBuffer];
  }

  CIContext *ctx = self.compositorCIContext ?: [CIContext context];
  CGImageRef cgImage = [ctx createCGImage:ciImage fromRect:ciImage.extent];

  if (!cgImage) {
    return [[FBSimulatorError describe:@"Failed to create CGImage from pixel buffer"] fail:error];
  }

  NSMutableData *pngData = [NSMutableData data];
  CGImageDestinationRef dest = CGImageDestinationCreateWithData((CFMutableDataRef)pngData, kUTTypePNG, 1, NULL);
  CGImageDestinationAddImage(dest, cgImage, NULL);
  BOOL finalized = CGImageDestinationFinalize(dest);
  CFRelease(dest);
  CGImageRelease(cgImage);

  if (!finalized) {
    return [[FBSimulatorError describe:@"Failed to encode PNG"] fail:error];
  }

  return pngData;
}

#pragma mark Stats

- (FBVideoEncoderStats)currentEncoderStats
{
  id<FBSimulatorVideoStreamFramePusher> pusher = self.framePusher;
  if (pusher && [pusher respondsToSelector:@selector(currentStats)]) {
    return [pusher currentStats];
  }
  FBVideoEncoderStats zeroed = {0};
  return zeroed;
}

- (FBFramebufferStats)currentFramebufferStats
{
  return [self.framebuffer currentStats];
}

- (NSUInteger)currentFrameNumber
{
  return self.frameNumber;
}

- (CFTimeInterval)currentTimeAtFirstFrame
{
  return self.timeAtFirstFrame;
}

- (CFTimeInterval)framebufferStatsStartTime
{
  return self.framebuffer.statsStartTime;
}

#pragma mark FBiOSTargetOperation

- (FBFuture<NSNull *> *)completed
{
  return [[FBMutableFuture.future
           resolveFromFuture:self.stoppedFuture]
          onQueue:self.writeQueue
          respondToCancellation:^{
            return [self stopStreaming];
          }];
}

@end

@implementation FBSimulatorVideoStream_Lazy

- (void)didReceiveDamageRect
{
  [self pushFrameForceKeyFrame:NO];
}

@end

@implementation FBSimulatorVideoStream_Eager

- (instancetype)initWithFramebuffer:(FBFramebuffer *)framebuffer configuration:(FBVideoStreamConfiguration *)configuration framesPerSecond:(NSUInteger)framesPerSecond edgeInsets:(FBVideoStreamEdgeInsets)edgeInsets writeQueue:(dispatch_queue_t)writeQueue logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithFramebuffer:framebuffer configuration:configuration edgeInsets:edgeInsets writeQueue:writeQueue logger:logger];
  if (!self) {
    return nil;
  }

  _framesPerSecond = framesPerSecond;

  return self;
}

#pragma mark Private

- (BOOL)mountSurface:(IOSurface *)surface error:(NSError **)error
{
  if (![super mountSurface:surface error:error]) {
    return NO;
  }

  self.framePusherThread = [[NSThread alloc] initWithBlock:^{
    [self runFramePushLoop];
  }];
  self.framePusherThread.qualityOfService = NSQualityOfServiceUserInteractive;
  [self.framePusherThread start];

  return YES;
}

- (NSDictionary<NSString *, id> *)compressionSessionProperties
{
  return @{
    (NSString *) kVTCompressionPropertyKey_ExpectedFrameRate : @(self.framesPerSecond),
    (NSString *) kVTCompressionPropertyKey_MaxKeyFrameInterval : @360,
  };
}

- (void)runFramePushLoop
{
  [[NSThread currentThread] setThreadPriority:1.0];
  NSUInteger fps = self.framesPerSecond;
  const uint64_t frameIntervalNanos = NSEC_PER_SEC / fps;

  mach_timebase_info_data_t timebase;
  mach_timebase_info(&timebase);
  const uint64_t frameIntervalMach = frameIntervalNanos * timebase.denom / timebase.numer;

  // Cadence stats (Welford's online algorithm for variance)
  const double statsIntervalSeconds = 5.0;
  const uint64_t statsIntervalMach = (uint64_t)(statsIntervalSeconds * 1e9) * timebase.denom / timebase.numer;
  uint64_t statsStartTime = mach_absolute_time();
  uint64_t pushCount = 0;
  uint64_t overrunCount = 0;
  uint64_t maxPushMach = 0;
  double pushMean = 0;  // Welford mean (in Mach ticks)
  double pushM2 = 0;    // Welford M2 (sum of squared deviations)

  uint64_t nextTargetTime = mach_absolute_time() + frameIntervalMach;
  while (self.stoppedFuture.state == FBFutureStateRunning) {
    uint64_t beforePush = mach_absolute_time();
    [self pushFrameForceKeyFrame:NO];
    uint64_t afterPush = mach_absolute_time();

    // Track push duration stats
    uint64_t pushDuration = afterPush - beforePush;
    pushCount++;
    if (pushDuration > maxPushMach) {
      maxPushMach = pushDuration;
    }
    double delta = (double)pushDuration - pushMean;
    pushMean += delta / (double)pushCount;
    pushM2 += delta * ((double)pushDuration - pushMean);

    // Sleep or log overrun
    if (afterPush < nextTargetTime) {
      mach_wait_until(nextTargetTime);
    } else {
      overrunCount++;
      uint64_t overrunNanos = (afterPush - nextTargetTime) * timebase.numer / timebase.denom;
      [self.logger log:[NSString stringWithFormat:@"Frame push exceeded budget by %.1f ms (budget: %.1f ms)",
                        overrunNanos / 1e6, frameIntervalNanos / 1e6]];
    }
    nextTargetTime += frameIntervalMach;

    // Periodic cadence stats
    if (afterPush - statsStartTime >= statsIntervalMach) {
      double toMs = (double)timebase.numer / (double)timebase.denom / 1e6;
      double avgMs = pushMean * toMs;
      double maxMs = (double)maxPushMach * toMs;
      double stddevMs = pushCount > 1 ? sqrt(pushM2 / (double)(pushCount - 1)) * toMs : 0;
      double intervalSeconds = (double)(afterPush - statsStartTime) * timebase.numer / timebase.denom / 1e9;
      [self.logger.info log:[NSString stringWithFormat:
                             @"Cadence stats (%.1fs): %llu pushes, %llu overruns, push duration avg %.1f ms / max %.1f ms, jitter stddev %.1f ms (budget: %.1f ms)",
                             intervalSeconds, pushCount, overrunCount, avgMs, maxMs, stddevMs, frameIntervalNanos / 1e6]];

      // Reset for next interval
      statsStartTime = afterPush;
      pushCount = 0;
      overrunCount = 0;
      maxPushMach = 0;
      pushMean = 0;
      pushM2 = 0;
    }
  }
}

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferVideo.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CVPixelBuffer.h>
#import <CoreVideo/CoreVideo.h>

#import "FBCapacityQueue.h"
#import "FBDiagnostic.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorLogger.h"

typedef NS_ENUM(NSInteger, FBFramebufferVideoState) {
  FBFramebufferVideoStateNotStarted = 0,
  FBFramebufferVideoStateRunning = 1,
  FBFramebufferVideoStateTerminated = 2,
};

static const OSType FBFramebufferPixelFormat = kCVPixelFormatType_32ARGB;
static const CMTimeScale FBFramebufferTimescale = 1000;

@interface FBFramebufferVideoItem : NSObject

@property (nonatomic, assign, readonly) CMTime time;
@property (nonatomic, assign, readonly) NSUInteger frameCount;
@property (nonatomic, assign, readonly) CGImageRef image;

- (instancetype)initWithTime:(CMTime)time image:(CGImageRef)image frameCount:(NSUInteger)frameCount;

@end

@implementation FBFramebufferVideoItem

- (instancetype)initWithTime:(CMTime)time image:(CGImageRef)image frameCount:(NSUInteger)frameCount
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _time = time;
  _frameCount = frameCount;
  _image = CGImageRetain(image);

  return self;
}

- (void)dealloc
{
  CGImageRelease(_image);
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Time %f | Count %lu", CMTimeGetSeconds(self.time), self.frameCount];
}

@end

@interface FBFramebufferVideo ()

@property (nonatomic, strong, readonly) FBDiagnostic *diagnostic;
@property (nonatomic, strong, readonly) id<FBSimulatorLogger> logger;
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;

@property (nonatomic, strong, readonly) dispatch_queue_t mediaQueue;
@property (nonatomic, strong, readonly) FBCapacityQueue *itemQueue;

@property (nonatomic, assign, readwrite) CMTimebaseRef timebase;
@property (nonatomic, strong, readwrite) FBFramebufferVideoItem *lastItem;

@property (nonatomic, strong, readwrite) AVAssetWriter *writer;
@property (nonatomic, strong, readwrite) AVAssetWriterInputPixelBufferAdaptor *adaptor;
@property (nonatomic, copy, readwrite) NSDictionary *pixelBufferAttributes;

@end

@implementation FBFramebufferVideo

#pragma mark Initializers

+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic logger:(id<FBSimulatorLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBSimulatorControl.media", DISPATCH_QUEUE_SERIAL);
  return [[self alloc] initWithDiagnostic:diagnostic onQueue:queue logger:[logger onQueue:queue] eventSink:eventSink];
}

- (instancetype)initWithDiagnostic:(FBDiagnostic *)diagnostic onQueue:(dispatch_queue_t)queue logger:(id<FBSimulatorLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _diagnostic = diagnostic;
  _logger = logger;
  _eventSink = eventSink;

  _mediaQueue = queue;
  _itemQueue = [FBCapacityQueue withCapacity:20];
  _timebase = NULL;

  return self;
}

#pragma mark FBFramebufferDelegate Implementation

- (void)framebufferDidUpdate:(FBSimulatorFramebuffer *)framebuffer withImage:(CGImageRef)image count:(NSUInteger)count size:(CGSize)size
{
  dispatch_async(self.mediaQueue, ^{
    // First frame means that the Video Session should be started.
    // The Frame will be enqueued with the time of the session start time.
    if (count == 0) {
      [self startRecordingWithImage:image size:size error:nil];
      return;
    }

    // Push the image at the current time.
    [self pushImage:image time:[self currentTime] frameCount:count];
  });
}

- (void)framebufferDidBecomeInvalid:(FBSimulatorFramebuffer *)framebuffer error:(NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
  dispatch_group_enter(teardownGroup);
  dispatch_barrier_async(self.mediaQueue, ^{
    if (self.lastItem) {
      CMTime time = [self currentTime];
      [self.logger.info logFormat:@"Pushing frame (%@) again at time %f as this is the final frame", self.lastItem, CMTimeGetSeconds(time)];
      [self pushImage:self.lastItem.image time:time frameCount:self.lastItem.frameCount + 1];
    }
    [self teardownWriterWithGroup:teardownGroup];
    dispatch_group_leave(teardownGroup);
  });
}

#pragma mark - Private

#pragma mark CMTime

- (CMTime)currentTime
{
  return CMTimebaseGetTimeWithTimeScale(self.timebase, FBFramebufferTimescale, kCMTimeRoundingMethod_QuickTime);
}

#pragma mark KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  NSParameterAssert([keyPath isEqualToString:@"readyForMoreMediaData"]);
  if (![change[NSKeyValueChangeNewKey] boolValue]) {
    return;
  }

  dispatch_async(self.mediaQueue, ^{
    [self drainQueue];
  });
}

#pragma mark Queueing

- (void)pushImage:(CGImageRef)image time:(CMTime)time frameCount:(NSUInteger)frameCount
{
  FBFramebufferVideoItem *item = [[FBFramebufferVideoItem alloc] initWithTime:time image:image frameCount:frameCount];
  FBFramebufferVideoItem *evictedItem = [self.itemQueue push:item];
  if (evictedItem) {
    [self.logger.debug logFormat:@"Evicted Frame (%@), frame dropped", item];
  }
  [self drainQueue];
}

- (void)drainQueue
{
  NSInteger drainCount = 0;
  while (self.adaptor.assetWriterInput.readyForMoreMediaData) {
    FBFramebufferVideoItem *item = [self.itemQueue pop];
    if (!item) {
      return;
    }
    drainCount++;

    // Create the pixel buffer from the buffer pool if the pool exists, otherwise create one.
    NSError *error = nil;
    CVPixelBufferRef pixelBuffer = self.adaptor.pixelBufferPool
      ? [FBFramebufferVideo createPixelBufferFromAdaptor:self.adaptor ofImage:item.image error:&error]
      : [FBFramebufferVideo createPixelBufferFromAttributes:self.pixelBufferAttributes ofImage:item.image error:&error];
    if (!pixelBuffer) {
      [self.logger.error logFormat:@"Could not construct a pixel buffer for frame (%@): %@", item, error];
      continue;
    }

    // It's important that a number of conditions are met to ensure that this call is reliable as possible.
    // Setting -[AVAssetWriter movieFragmentInterval] usually exacerbates any problems in the input.
    // Much of the information here comes from the AVFoundation guru @rfistman.
    //
    // 1) The time used in -[AVAssetWriter startSessionAtSourceTime:] should have the same value as the first call to -[AVAssetWriterInputPixelBufferAdaptor appendPixelBuffer:withPresentationTime:]
    // 2) The ordering of frames should always mean that each frame is sequential in it's presentation time. kCMTimeRoundingMethod_Default can result in strange values from rounding so kCMTimeRoundingMethod_RoundTowardNegativeInfinity is used.
    //
    // "The operation couldn't be completed. (OSStatus error -12633.)" is 'InvalidTimestamp': http://stackoverflow.com/a/23252239
    // "An unknown error occurred (-16341)" is 'kMediaSampleTimingGeneratorError_InvalidTimeStamp': @rfistman

    if (self.lastItem && CMTimeCompare(item.time, self.lastItem.time) != 1) {
      [self.logger.error logFormat:@"Dropping Frame (%@) as it's timestamp is not greater than a previous frame (%@)", item, self.lastItem];
    } else if (![self.adaptor appendPixelBuffer:pixelBuffer withPresentationTime:item.time]) {
      [self.logger.error logFormat:@"Failed to append pixel buffer of frame (%@) with error %@", item, self.writer.error];
    }
    self.lastItem = item;
    CVPixelBufferRelease(pixelBuffer);
  }
  if (drainCount == 0 && self.itemQueue.count > 0) {
    [self.logger.debug logFormat:@"Failed to drain any frames with a queue of length %lu", drainCount];
  }
}

#pragma mark Writer Lifecycle

- (BOOL)startRecordingWithImage:(CGImageRef)image size:(CGSize)size error:(NSError **)error
{
  // Create a Timebase to construct the time of the first frame.
  CMTimebaseRef timebase = NULL;
  CMTimebaseCreateWithMasterClock(
    kCFAllocatorDefault,
    CMClockGetHostTimeClock(),
    &timebase
  );
  NSAssert(timebase, @"Expected to be able to construct timebase");
  CMTimebaseSetRate(timebase, 1.0);
  self.timebase = timebase;

  // Construct time for the enqueing of the first frame as well as the session start.
  CMTime time = CMTimeMakeWithSeconds(0, FBFramebufferTimescale);

  // Create the asset writer.
  FBDiagnosticBuilder *logBuilder = [FBDiagnosticBuilder builderWithDiagnostic:self.diagnostic];
  NSString *path = logBuilder.createPath;
  if (![self createAssetWriterAtPath:path size:size startTime:time error:error]) {
    return NO;
  }

  // Enqueue the first frame
  [self pushImage:image time:time frameCount:0];

  // Report the availability of the video
  [self.eventSink diagnosticAvailable:[[logBuilder updatePath:path] build]];

  return YES;
}

- (BOOL)createAssetWriterAtPath:(NSString *)videoPath size:(CGSize)size startTime:(CMTime)startTime error:(NSError **)error
{
  NSError *innerError = nil;
  NSURL *url = [NSURL fileURLWithPath:videoPath];
  AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeQuickTimeMovie error:&innerError];
  if (!writer) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to create an asset writer at %@", videoPath]
      causedBy:innerError]
      failBool:error];
  }

  // Create an Input for the Writer
  NSDictionary *outputSettings = @{
    AVVideoCodecKey : AVVideoCodecH264,
    AVVideoWidthKey : @(size.width),
    AVVideoHeightKey : @(size.height),
  };
  AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:outputSettings];
  input.expectsMediaDataInRealTime = NO;
  if (![writer canAddInput:input]) {
    return [[FBSimulatorError
      describeFormat:@"Not permitted to add writer input at %@", input]
      failBool:error];
  }
  [writer addInput:input];

  // Create an adaptor for writing to the input via concrete pixel buffers
  self.pixelBufferAttributes =  @{
    (NSString *) kCVPixelBufferCGImageCompatibilityKey:(id)kCFBooleanTrue,
    (NSString *) kCVPixelBufferCGBitmapContextCompatibilityKey:(id)kCFBooleanTrue,
    (NSString *) kCVPixelBufferWidthKey : @(size.width),
    (NSString *) kCVPixelBufferHeightKey : @(size.height),
    (NSString *) kCVPixelBufferPixelFormatTypeKey : @(FBFramebufferPixelFormat)
  };
  AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
   assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
   sourcePixelBufferAttributes:self.pixelBufferAttributes];

  // If the file exists at the path it must be removed first.
  NSFileManager *fileManager = NSFileManager.defaultManager;
  if ([fileManager fileExistsAtPath:videoPath] && ![fileManager removeItemAtPath:videoPath error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to remove item at path %@ prior to deletion", videoPath]
      causedBy:innerError]
      failBool:error];
  }

  // Start the Writer and the Session
  if (![writer startWriting]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to start writing to the writer %@ error code %ld", writer, writer.status]
      causedBy:writer.error]
      failBool:error];
  }
  [writer startSessionAtSourceTime:startTime];

  // Success means the state needs to be set.
  self.writer = writer;
  self.adaptor = adaptor;
  [writer addObserver:self forKeyPath:@"readyForMoreMediaData" options:NSKeyValueObservingOptionNew context:NULL];

  // Log the success
  [self.logger.info logFormat:@"Started Recording video at path %@", videoPath];

  return YES;
}

- (void)teardownWriterWithGroup:(dispatch_group_t)teardownGroup
{
  [self.logger.info logFormat:@"Marking video at '%@ as finished", self.writer.outputURL];
  [self.adaptor.assetWriterInput markAsFinished];
  [self.writer removeObserver:self forKeyPath:@"readyForMoreMediaData"];

  [self.logger.info logFormat:@"Finishing Writing '%@'", self.writer.outputURL];
  dispatch_group_enter(teardownGroup);
  [self.writer finishWritingWithCompletionHandler:^{
    [self.logger.info logFormat:@"Finished Writing '%@'", self.writer.outputURL];
    dispatch_group_leave(teardownGroup);
  }];
}

#pragma mark Pixel Buffers

+ (CVPixelBufferRef)createPixelBufferFromAttributes:(NSDictionary *)attributes ofImage:(CGImageRef)image error:(NSError **)error
{
  size_t width = (size_t) [attributes[(NSString *) kCVPixelBufferWidthKey] unsignedLongValue];
  size_t height = (size_t) [attributes[(NSString *) kCVPixelBufferHeightKey] unsignedLongValue];
  OSType pixelFormat = [attributes[(NSString *) kCVPixelBufferPixelFormatTypeKey] unsignedIntValue];

  // Create the Pixel Buffer, caller will release.
  CVPixelBufferRef pixelBuffer = NULL;
  CVReturn status = CVPixelBufferCreate(
    kCFAllocatorDefault,
    width,
    height,
    pixelFormat,
    (__bridge CFDictionaryRef) attributes,
    &pixelBuffer
  );
  if (status != kCVReturnSuccess) {
    [[FBSimulatorError describeFormat:@"CVPixelBufferCreate returned non-success status %d", status] fail:error];
    return NULL;
  }

  return [self writeImage:image ofSize:CGSizeMake(width, height) intoPixelBuffer:pixelBuffer];
}

+ (CVPixelBufferRef)createPixelBufferFromAdaptor:(AVAssetWriterInputPixelBufferAdaptor *)adaptor ofImage:(CGImageRef)image error:(NSError **)error
{
  if (!adaptor.pixelBufferPool) {
    [[FBSimulatorError describe:@"-[AVAssetWriterInputPixelBufferAdaptor pixelBufferPool] is nil"] fail:error];
    return NULL;
  }

  // Get the pixel buffer from the pool
  CVPixelBufferRef pixelBuffer = NULL;
  CVReturn status = CVPixelBufferPoolCreatePixelBuffer(
    NULL,
    adaptor.pixelBufferPool,
    &pixelBuffer
  );
  if (status != kCVReturnSuccess) {
    [[FBSimulatorError describeFormat:@"CVPixelBufferPoolCreatePixelBuffer returned non-success status %d", status] fail:error];
    return NULL;
  }

  size_t width = (size_t) [adaptor.sourcePixelBufferAttributes[(NSString *) kCVPixelBufferWidthKey] unsignedLongValue];
  size_t height = (size_t) [adaptor.sourcePixelBufferAttributes[(NSString *) kCVPixelBufferHeightKey] unsignedLongValue];
  return [self writeImage:image ofSize:CGSizeMake(width, height) intoPixelBuffer:pixelBuffer];
}

+ (CVPixelBufferRef)writeImage:(CGImageRef)image ofSize:(CGSize)size intoPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
  // Get and lock the buffer.
  CVPixelBufferLockBaseAddress(pixelBuffer, 0);
  void *buffer = CVPixelBufferGetBaseAddress(pixelBuffer);

  // Create a graphics context based on the pixel buffer.
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(
    buffer,
    (size_t) size.width,
    (size_t) size.height,
    8, // See CGBitmapContextCreate documentation
    CVPixelBufferGetBytesPerRow(pixelBuffer),
    colorSpace,
    (CGBitmapInfo) kCGImageAlphaNoneSkipFirst
  );

  // Draw to it.
  CGRect rect = { .size = size, .origin = CGPointZero };
  CGContextDrawImage(
    context,
    rect,
    image
  );

  // Cleanup.
  CGColorSpaceRelease(colorSpace);
  CGContextRelease(context);
  CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

  return pixelBuffer;
}

@end

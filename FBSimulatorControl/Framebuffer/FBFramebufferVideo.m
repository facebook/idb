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
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorLogger.h"
#import "FBWritableLog.h"

typedef NS_ENUM(NSInteger, FBFramebufferVideoState) {
  FBFramebufferVideoStateNotStarted = 0,
  FBFramebufferVideoStateRunning = 1,
  FBFramebufferVideoStateTerminated = 2,
};

static const OSType FBFramebufferPixelFormat = kCVPixelFormatType_32ARGB;
static const CMTimeScale FBFramebufferTimescale = 1000000000;
static const Float64 FBFramebufferFragmentIntervalSeconds = 5;

@interface FBFramebufferVideoItem : NSObject

@property (nonatomic, assign, readonly) CMTime time;
@property (nonatomic, assign, readonly) CGImageRef image;

- (instancetype)initWithTime:(CMTime)time image:(CGImageRef)image;

@end

@implementation FBFramebufferVideoItem

- (instancetype)initWithTime:(CMTime)time image:(CGImageRef)image
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _time = time;
  _image = CGImageRetain(image);

  return self;
}

- (void)dealloc
{
  CGImageRelease(_image);
}

@end

@interface FBFramebufferVideo ()

@property (nonatomic, strong, readonly) FBWritableLog *writableLog;
@property (nonatomic, assign, readonly) CGFloat scale;
@property (nonatomic, strong, readonly) id<FBSimulatorLogger> logger;
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;

@property (nonatomic, strong, readonly) dispatch_queue_t mediaQueue;
@property (nonatomic, strong, readonly) FBCapacityQueue *itemQueue;

@property (nonatomic, assign, readwrite) CMTimebaseRef timebase;
@property (nonatomic, assign, readwrite) CGSize size;

@property (nonatomic, strong, readwrite) AVAssetWriter *writer;
@property (nonatomic, strong, readwrite) AVAssetWriterInput *input;
@property (nonatomic, strong, readwrite) AVAssetWriterInputPixelBufferAdaptor *adaptor;

@end

@implementation FBFramebufferVideo

#pragma mark Initializers

+ (instancetype)withWritableLog:(FBWritableLog *)writableLog scale:(CGFloat)scale logger:(id<FBSimulatorLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
{
  return [[self alloc] initWithWritableLog:writableLog scale:scale logger:logger eventSink:eventSink];
}

- (instancetype)initWithWritableLog:(FBWritableLog *)writableLog scale:(CGFloat)scale logger:(id<FBSimulatorLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _writableLog = writableLog;
  _scale = scale;
  _logger = logger;
  _eventSink = eventSink;
  _mediaQueue = dispatch_queue_create("com.facebook.FBSimulatorControl.media", DISPATCH_QUEUE_SERIAL);
  _itemQueue = [FBCapacityQueue withCapacity:20];

  _size = CGSizeZero;

  return self;
}

#pragma mark Public Methods

- (BOOL)stopRecordingWithError:(NSError **)error
{
  __block BOOL success = NO;
  // A barrier is used to ensure the contract of finishWritingWithCompletionHandler: is fulfilled:
  // "To guarantee that all sample buffers are successfully written, you must ensure that all calls to appendSampleBuffer: and appendPixelBuffer:withPresentationTime: have returned"
  dispatch_barrier_sync(self.mediaQueue, ^{
    if (!self.writer) {
      success = [[FBSimulatorError describe:@"Cannot stop recording when it hasn't started"] failBool:error];
      return;
    }
    [self teardownWriter];
    success = YES;
  });
  return success;
}

#pragma mark FBFramebufferDelegate Implementation

- (void)framebuffer:(FBSimulatorFramebuffer *)framebuffer didGetSize:(CGSize)size
{
  dispatch_async(self.mediaQueue, ^{
    NSParameterAssert(CGSizeEqualToSize(self.size, CGSizeZero));
    self.size = CGSizeMake(ceil(size.width * self.scale), ceil(size.height * self.scale));
    [self startRecordingWithError:nil];
  });
}

- (void)framebufferDidUpdate:(FBSimulatorFramebuffer *)framebuffer withImage:(CGImageRef)image size:(CGSize)size
{
  dispatch_async(self.mediaQueue, ^{
    // Don't append frames if the writer hasn't been constructed yet.s
    if (!self.writer) {
      return;
    }

    // Create an item and place it in the queue.
    CMTime time = CMTimebaseGetTimeWithTimeScale(self.timebase, FBFramebufferTimescale, kCMTimeRoundingMethod_Default);
    FBFramebufferVideoItem *item = [[FBFramebufferVideoItem alloc] initWithTime:time image:image];
    FBFramebufferVideoItem *evictedItem = [self.itemQueue push:item];
    if (evictedItem) {
      [self.logger.debug logFormat:@"Evicted frame at time %f, frame dropped", CMTimeGetSeconds(item.time)];
    }

    [self drainQueue];
  });
}

- (void)framebufferDidBecomeInvalid:(FBSimulatorFramebuffer *)framebuffer error:(NSError *)error
{
  dispatch_barrier_async(self.mediaQueue, ^{
    [self teardownWriter];
  });
}

#pragma mark Private

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

- (NSDictionary *)pixelBufferAttributes
{
  CGSize size = self.size;
  return @{
    (NSString *) kCVPixelBufferCGImageCompatibilityKey:(id)kCFBooleanTrue,
    (NSString *) kCVPixelBufferCGBitmapContextCompatibilityKey:(id)kCFBooleanTrue,
    (NSString *) kCVPixelBufferWidthKey : @(size.width),
    (NSString *) kCVPixelBufferHeightKey : @(size.height),
    (NSString *) kCVPixelBufferPixelFormatTypeKey : @(FBFramebufferPixelFormat)
  };
}

- (void)drainQueue
{
  while (self.input.readyForMoreMediaData) {
    FBFramebufferVideoItem *item = [self.itemQueue pop];
    if (!item) {
      return;
    }
    CVPixelBufferRef pixelBuffer = [FBFramebufferVideo createPixelBufferOfSize:self.size attributes:self.pixelBufferAttributes ofImage:item.image];
    if (!pixelBuffer) {
      return;
    }
    if (![self.adaptor appendPixelBuffer:pixelBuffer withPresentationTime:item.time]) {
      [self.logger.error logFormat:@"Failed to append frame at time %f seconds of pixel buffer with error %@", CMTimeGetSeconds(item.time), self.writer.error];
    }
    CVPixelBufferRelease(pixelBuffer);
  }
}

- (BOOL)startRecordingWithError:(NSError **)error
{
  // Confirm that framebuffer size info is available
  if (CGSizeEqualToSize(CGSizeZero, self.size)) {
    return [[[FBSimulatorError describe:@"Video size not yet available, cannot record"] logger:self.logger] failBool:error];
  }

  // Create a timebase that has now as the start.
  CMTimebaseRef timebase = NULL;
  CMTimebaseCreateWithMasterClock(
    kCFAllocatorDefault,
    CMClockGetHostTimeClock(),
    &timebase
  );
  NSAssert(timebase, @"Expected to be able to construct timebase");
  CMTimebaseSetRate(timebase, 1.0);
  self.timebase = timebase;

  // Create the asset writer.
  FBWritableLogBuilder *logBuilder = [FBWritableLogBuilder builderWithWritableLog:self.writableLog];
  NSString *path = logBuilder.createPath;
  if (![self createAssetWriterAtPath:path size:self.size error:error]) {
    return NO;
  }

  // Report the availability of the video
  [self.eventSink logAvailable:[[logBuilder updatePath:path] build]];

  return YES;
}

- (BOOL)createAssetWriterAtPath:(NSString *)videoPath size:(CGSize)size error:(NSError **)error
{
  // Create an Asset Writer to a file
  NSError *innerError = nil;
  NSURL *url = [NSURL fileURLWithPath:videoPath];
  AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeMPEG4 error:&innerError];
  if (!writer) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to create an asset writer at %@", videoPath]
      causedBy:innerError]
      failBool:error];
  }
  // Setting a Fragment interval will ensure there is a video if the process crashes.
  // However, setting this appears to make the output fail if the fragment interval is too low.
  writer.movieFragmentInterval = CMTimeMakeWithSeconds(FBFramebufferFragmentIntervalSeconds, FBFramebufferTimescale);

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
  AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
   assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
   sourcePixelBufferAttributes:nil];

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
  [writer startSessionAtSourceTime:kCMTimeZero];

  // Success means the state needs to be set.
  self.writer = writer;
  self.input = input;
  self.adaptor = adaptor;
  [writer addObserver:self forKeyPath:@"readyForMoreMediaData" options:NSKeyValueObservingOptionNew context:NULL];

  // Log the success
  [self.logger.info logFormat:@"Started Recording video at path %@", videoPath];

  return YES;
}

- (void)teardownWriter
{
  AVAssetWriter *writer = self.writer;
  AVAssetWriterInput *input = self.input;
  self.writer = nil;
  self.adaptor = nil;
  self.input = nil;

  [input markAsFinished];
  [writer removeObserver:self forKeyPath:@"readyForMoreMediaData"];
  [writer finishWritingWithCompletionHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.logger.info log:@"Finished Recording"];
    });
  }];
}

+ (CVPixelBufferRef)createPixelBufferOfSize:(CGSize)size attributes:(NSDictionary *)attributes ofImage:(CGImageRef)image
{
  size_t width = (size_t) size.width;
  size_t height = (size_t) size.height;
  OSType pixelFormat = FBFramebufferPixelFormat;

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
    return NULL;
  }

  return [self writeImage:image ofSize:size intoPixelBuffer:pixelBuffer];
}

+ (CVPixelBufferRef)createPixelBufferOfSize:(CGSize)size fromPool:(CVPixelBufferPoolRef)pool ofImage:(CGImageRef)image
{
  // Get the pixel buffer from the pool
  CVPixelBufferRef pixelBuffer = NULL;
  CVReturn status = CVPixelBufferPoolCreatePixelBuffer(
    NULL,
    pool,
    &pixelBuffer
  );
  if (status != kCVReturnSuccess) {
    return NULL;
  }

  return [self writeImage:image ofSize:size intoPixelBuffer:pixelBuffer];
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

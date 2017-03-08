/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferFrameGenerator.h"

#import <CoreMedia/CoreMedia.h>
#import <CoreImage/CoreImage.h>

#import <FBControlCore/FBControlCore.h>

#import <SimulatorKit/SimDeviceFramebufferBackingStore+Removed.h>

#import "FBFramebufferFrame.h"
#import "FBFramebufferFrameSink.h"
#import "FBSurfaceImageGenerator.h"

static const NSInteger FBFramebufferLogFrameFrequency = 100;
// Timescale is in nanoseconds
static const CMTimeScale FBSimulatorFramebufferTimescale = 10E8;
static const CMTimeRoundingMethod FBSimulatorFramebufferRoundingMethod = kCMTimeRoundingMethod_Default;
static const uint64_t FBSimulatorFramebufferFrameTimeInterval = NSEC_PER_MSEC * 20;

@interface FBFramebufferFrameGenerator ()

@property (nonatomic, copy, readonly) NSDecimalNumber *scale;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@property (atomic, assign, readwrite) CMTimebaseRef timebase;
@property (atomic, assign, readwrite) NSUInteger frameCount;
@property (atomic, assign, readwrite) CGSize size;

@end

@implementation FBFramebufferFrameGenerator

#pragma mark Initializers

+ (instancetype)generatorWithScale:(NSDecimalNumber *)scale sink:(id<FBFramebufferFrameSink>)sink queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithScale:scale sink:sink queue:queue logger:logger];
}

- (instancetype)initWithScale:(NSDecimalNumber *)scale sink:(id<FBFramebufferFrameSink>)sink queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _scale = scale;
  _sink = sink;
  _queue = queue;
  _logger = logger;

  _frameCount = 0;
  _size = CGSizeZero;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Size %@ | Frame Count %ld",
    NSStringFromSize(self.size),
    self.frameCount
  ];
}

#pragma mark FBJSONSerializable Implementation

- (id)jsonSerializableRepresentation
{
  return @{
    @"size" : NSStringFromSize(self.size)
  };
}

#pragma mark Public Methods

- (void)frameSteamEndedWithTeardownGroup:(dispatch_group_t)group error:(NSError *)error
{
  dispatch_group_async(group, self.queue, ^{
    if (self.timebase) {
      CFRelease(self.timebase);
      self.timebase = nil;
    }
    [self frameSteamEndedWithTeardownGroup:group error:error];
  });
}

#pragma mark Private

- (void)startTimebaseNow
{
  NSParameterAssert(self.timebase == NULL);

  CMTimebaseRef timebase = NULL;
  CMTimebaseCreateWithMasterClock(
    kCFAllocatorDefault,
    CMClockGetHostTimeClock(),
    &timebase
  );
  NSAssert(timebase, @"Expected to be able to construct timebase");
  CMTimebaseSetRate(timebase, 1.0);
  self.timebase = timebase;
}

- (void)pushNewFrameFromCurrentTimeWithCGImage:(CGImageRef)image size:(CGSize)size
{
  // If there's no timebase, we shouldn't be pushing any frames.
  NSParameterAssert(self.timebase);

  // Create the Frame and pass it to the sink
  FBFramebufferFrame *frame = [self frameFromCurrentTime:image size:size];
  [self.sink frameGenerator:self didUpdate:frame];

  // Log and increment.
  if (self.frameCount == 0) {
    [self.logger.info log:@"First Frame"];
  }
  else if (self.frameCount % FBFramebufferLogFrameFrequency == 0) {
    [self.logger.info logFormat:@"Frame Count %lu", self.frameCount];
  }
  self.frameCount = self.frameCount + 1;
}

- (FBFramebufferFrame *)frameFromCurrentTime:(CGImageRef)image size:(CGSize)size
{
  CMTime time = CMTimebaseGetTimeWithTimeScale(self.timebase, FBSimulatorFramebufferTimescale, FBSimulatorFramebufferRoundingMethod);
  return [[FBFramebufferFrame alloc] initWithTime:time timebase:self.timebase image:image count:self.frameCount size:size];
}

@end

@implementation FBFramebufferBackingStoreFrameGenerator

#pragma mark Public Methods

- (void)firstFrameWithBackingStore:(SimDeviceFramebufferBackingStore *)backingStore
{
  [self startTimebaseNow];
  [self pushNewFrameFromCurrentTimeWithBackingStore:backingStore];
}

- (void)backingStoreDidUpdate:(SimDeviceFramebufferBackingStore *)backingStore
{
  [self pushNewFrameFromCurrentTimeWithBackingStore:backingStore];
}

#pragma mark Private

- (void)pushNewFrameFromCurrentTimeWithBackingStore:(SimDeviceFramebufferBackingStore *)backingStore
{
  CGSize size = NSMakeSize(backingStore.pixelsWide, backingStore.pixelsHigh);
  self.size = size;
  [self pushNewFrameFromCurrentTimeWithCGImage:backingStore.image size:size];
}

@end

@interface FBFramebufferIOSurfaceFrameGenerator ()

@property (nonatomic, strong, readonly) dispatch_source_t timerSource;
@property (nonatomic, strong, readonly) FBSurfaceImageGenerator *imageGenerator;

@end

@implementation FBFramebufferIOSurfaceFrameGenerator

#pragma mark Lifecycle

- (instancetype)initWithScale:(NSDecimalNumber *)scale sink:(id<FBFramebufferFrameSink>)sink queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithScale:scale sink:sink queue:queue logger:logger];
  if (!self) {
    return nil;
  }

  // Only rescale if the original scale is different to 1.
  _timerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
  dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW, FBSimulatorFramebufferFrameTimeInterval);
  dispatch_source_set_timer(_timerSource, startTime, FBSimulatorFramebufferFrameTimeInterval, 0);

  __weak typeof(self) weakSelf = self;
  dispatch_source_set_event_handler(_timerSource, ^{
    [weakSelf pushNewFrameFromCurrentTime];
  });

  return self;
}

#pragma mark Public

- (void)currentSurfaceChanged:(nullable IOSurfaceRef)surface
{
  [self.imageGenerator currentSurfaceChanged:surface];
  if (surface == NULL) {
    dispatch_suspend(self.timerSource);
  } else {
    [self startTimebaseNow];
    [self pushNewFrameFromCurrentTime];
    dispatch_resume(self.timerSource);
  }
}

- (void)frameSteamEndedWithTeardownGroup:(dispatch_group_t)group error:(NSError *)error
{
  [super frameSteamEndedWithTeardownGroup:group error:error];

  if (self.timerSource) {
    dispatch_source_cancel(self.timerSource);
    _timerSource = nil;
  }
  [self currentSurfaceChanged:nil];
}

#pragma mark Private

- (void)pushNewFrameFromCurrentTime
{
  CGImageRef image = [self.imageGenerator availableImage];
  if (!image) {
    return;
  }
  CGSize size = CGSizeMake(CGImageGetWidth(image), CGImageGetWidth(image));
  [self pushNewFrameFromCurrentTimeWithCGImage:image size:size];
}

@end

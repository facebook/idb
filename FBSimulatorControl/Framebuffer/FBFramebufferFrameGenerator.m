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

#import <SimulatorKit/SimDeviceFramebufferService.h>
#import <SimulatorKit/SimDeviceFramebufferService+Removed.h>
#import <SimulatorKit/SimDeviceFramebufferBackingStore+Removed.h>

#import "FBFramebufferFrame.h"
#import "FBSurfaceImageGenerator.h"

/**
 Enumeration to keep track of internal state.
 */
typedef NS_ENUM(NSUInteger, FBFramebufferServiceState) {
  FBFramebufferServiceStateNotStarted = 0, /** Before the framebuffer is 'listening'. */
  FBFramebufferServiceStateStarting = 1, /** After the framebuffer has started, but before the first frame. */
  FBFramebufferServiceStateRunning = 2, /** After the framebuffer has started, but before the first frame. */
  FBFramebufferServiceStateTerminated = 3, /** After the framebuffer has terminated. */
};

static const NSInteger FBFramebufferLogFrameFrequency = 100;
// Timescale is in nanoseconds
static const CMTimeScale FBSimulatorFramebufferTimescale = 10E8;
static const CMTimeRoundingMethod FBSimulatorFramebufferRoundingMethod = kCMTimeRoundingMethod_Default;
static const uint64_t FBSimulatorFramebufferFrameTimeInterval = NSEC_PER_MSEC * 20;

@interface FBFramebufferFrameGenerator () <FBFramebufferFrameSink>

@property (nonatomic, copy, readonly) NSDecimalNumber *scale;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) NSMutableArray<id<FBFramebufferFrameSink>> *attachedSinks;

@property (atomic, assign, readwrite) FBFramebufferServiceState state;
@property (atomic, assign, readwrite) CMTimebaseRef timebase;
@property (atomic, assign, readwrite) NSUInteger frameCount;
@property (atomic, assign, readwrite) CGSize size;

@end

@interface FBFramebufferBackingStoreFrameGenerator ()

@property (nonatomic, strong, readonly) SimDeviceFramebufferService *service;

@end

@interface FBFramebufferIOSurfaceFrameGenerator ()

@property (nonatomic, strong, readonly) FBFramebufferSurface *surface;
@property (nonatomic, strong, readonly) FBSurfaceImageGenerator *imageGenerator;
@property (nonatomic, strong, readonly) FBDispatchSourceNotifier *timer;

@end

@implementation FBFramebufferFrameGenerator

#pragma mark Initializers

- (instancetype)initWithScale:(NSDecimalNumber *)scale queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _scale = scale;
  _queue = queue;
  _logger = logger;

  _state = FBFramebufferServiceStateNotStarted;
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

- (void)attachSink:(id<FBFramebufferFrameSink>)sink
{
  dispatch_async(self.queue, ^{
    // Don't attach sinks if we're invalid
    if (self.state == FBFramebufferServiceStateTerminated) {
      return;
    }
    // Attach the Sink
    [self.attachedSinks addObject:sink];
    // The first Sink applies backpressure, start the consumption.
    if (self.attachedSinks.count && self.state == FBFramebufferServiceStateNotStarted) {
      [self firstConsumerAttached];
    }
  });
}

- (void)detachSink:(id<FBFramebufferFrameSink>)sink
{
  dispatch_async(self.queue, ^{
    [self.attachedSinks removeObject:sink];
  });
}

- (void)teardownWithGroup:(dispatch_group_t)teardownGroup
{
  dispatch_group_async(teardownGroup, self.queue, ^{
    if (self.state == FBFramebufferServiceStateTerminated) {
      return;
    }
    [self detachAllConsumers:teardownGroup];
  });
}

#pragma mark Private

- (void)firstConsumerAttached
{
  self.state = FBFramebufferServiceStateStarting;
}

- (void)detachAllConsumers:(dispatch_group_t)teardownGroup
{
  if (self.timebase) {
    CFRelease(self.timebase);
    self.timebase = nil;
  }
  [self frameGenerator:self didBecomeInvalidWithError:nil teardownGroup:teardownGroup];
  [self.attachedSinks removeAllObjects];
  self.state = FBFramebufferServiceStateTerminated;
}

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
  [self frameGenerator:self didUpdate:frame];

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

#pragma mark Forwarding to Sinks

- (void)frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator didUpdate:(FBFramebufferFrame *)frame
{
  @synchronized (self.attachedSinks)
  {
    for (id<FBFramebufferFrameSink> sink in self.attachedSinks) {
      [sink frameGenerator:frameGenerator didUpdate:frame];
    }
  }
}

- (void)frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator didBecomeInvalidWithError:(NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
  @synchronized (self.attachedSinks)
  {
    for (id<FBFramebufferFrameSink> sink in self.attachedSinks) {
      [sink frameGenerator:frameGenerator didBecomeInvalidWithError:error teardownGroup:teardownGroup];
    }
  }
}

#pragma mark Private

+ (NSString *)stringFromFramebufferState:(FBFramebufferServiceState)state
{
  switch (state) {
    case FBFramebufferServiceStateNotStarted:
      return @"Not Started";
    case FBFramebufferServiceStateStarting:
      return @"Starting";
    case FBFramebufferServiceStateRunning:
      return @"Running";
    case FBFramebufferServiceStateTerminated:
      return @"Terminated";
    default:
      return @"Unknown";
  }
}

@end

@implementation FBFramebufferBackingStoreFrameGenerator

#pragma mark Initializers

+ (instancetype)generatorWithFramebufferService:(SimDeviceFramebufferService *)service scale:(NSDecimalNumber *)scale queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithFramebufferService:service scale:scale queue:queue logger:logger];
}

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)service scale:(NSDecimalNumber *)scale queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithScale:scale queue:queue logger:logger];
  if (!self) {
    return nil;
  }

  _service = service;

  return self;
}

#pragma mark Client Callbacks from SimDeviceFramebufferService

- (void)framebufferService:(SimDeviceFramebufferService *)service didUpdateRegion:(CGRect)region ofBackingStore:(SimDeviceFramebufferBackingStore *)backingStore
{
  // We recieve the backing store on the first surface.
  if (self.state == FBFramebufferServiceStateStarting) {
    self.state = FBFramebufferServiceStateRunning;
    [self firstFrameWithBackingStore:backingStore];
  } else if (self.state == FBFramebufferServiceStateRunning) {
    [self backingStoreDidUpdate:backingStore];
  }
}

- (void)framebufferService:(SimDeviceFramebufferService *)service didRotateToAngle:(double)angle
{

}

- (void)framebufferService:(SimDeviceFramebufferService *)service didFailWithError:(NSError *)error
{
  dispatch_group_t group = dispatch_group_create();
  [self teardownWithGroup:group];
}

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

- (void)firstConsumerAttached
{
  [self.service registerClient:self onQueue:self.queue];
  [self.service resume];
}

- (void)detachAllConsumers:(dispatch_group_t)teardownGroup
{
  [self.service suspend];
}

- (void)pushNewFrameFromCurrentTimeWithBackingStore:(SimDeviceFramebufferBackingStore *)backingStore
{
  CGSize size = NSMakeSize(backingStore.pixelsWide, backingStore.pixelsHigh);
  self.size = size;
  [self pushNewFrameFromCurrentTimeWithCGImage:backingStore.image size:size];
}

@end

@implementation FBFramebufferIOSurfaceFrameGenerator

#pragma mark Initializers

+ (instancetype)generatorWithRenderable:(FBFramebufferSurface *)surface scale:(NSDecimalNumber *)scale queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithRenderable:surface scale:scale queue:queue logger:logger];
}

- (instancetype)initWithRenderable:(FBFramebufferSurface *)surface scale:(NSDecimalNumber *)scale queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithScale:scale queue:queue logger:logger];
  if (!self) {
    return nil;
  }

  _surface = surface;
  __weak typeof(self) weakSelf = self;
  _timer = [FBDispatchSourceNotifier timerNotifierNotifierWithTimeInterval:FBSimulatorFramebufferFrameTimeInterval queue:self.queue handler:^(FBDispatchSourceNotifier *_) {
    [weakSelf pushNewFrameFromCurrentTime];
  }];
  return self;
}

#pragma mark FBFramebufferSurfaceConsumer

- (void)didChangeIOSurface:(nullable IOSurfaceRef)surface
{
  [self.imageGenerator didChangeIOSurface:surface];
  dispatch_source_t timerSource = self.timer.dispatchSource;
  if (surface == NULL && timerSource != nil) {
    dispatch_suspend(timerSource);
  } else if (timerSource != nil) {
    [self startTimebaseNow];
    [self pushNewFrameFromCurrentTime];
    dispatch_resume(timerSource);
  }
}

- (void)didReceiveDamageRect:(CGRect)rect
{
  [self.imageGenerator didReceiveDamageRect:rect];
}

- (NSString *)consumerIdentifier
{
  return NSStringFromClass(self.class);
}

#pragma mark Private

- (void)firstConsumerAttached
{
  [super firstConsumerAttached];

  // Start Consuming
  [self.surface attachConsumer:self onQueue:self.queue];
}

- (void)detachAllConsumers:(dispatch_group_t)teardownGroup
{
  [super detachAllConsumers:teardownGroup];

  // Stop Consuming
  [self.surface detachConsumer:self];

  // Tear down the rest
  if (self.timer) {
    [self.timer terminate];
    _timer = nil;
  }
  [self didChangeIOSurface:nil];
}

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

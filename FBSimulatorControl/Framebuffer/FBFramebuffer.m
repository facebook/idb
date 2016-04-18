/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebuffer.h"

#import <mach/exc.h>
#import <mach/mig.h>

#import <Cocoa/Cocoa.h>

#import <FBControlCore/FBControlCore.h>

#import <SimulatorKit/SimDeviceFramebufferBackingStore.h>
#import <SimulatorKit/SimDeviceFramebufferService.h>

#import "FBFramebufferCompositeDelegate.h"
#import "FBFramebufferDebugWindow.h"
#import "FBFramebufferDelegate.h"
#import "FBFramebufferFrame.h"
#import "FBFramebufferImage.h"
#import "FBFramebufferVideo.h"
#import "FBFramebufferVideoConfiguration.h"
#import "FBSimulator.h"
#import "FBSimulatorDiagnostics.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorLaunchConfiguration.h"

/**
 Enumeration to keep track of internal state.
 */
typedef NS_ENUM(NSUInteger, FBSimulatorFramebufferState) {
  FBSimulatorFramebufferStateNotStarted = 0, /** Before the framebuffer is 'listening'. */
  FBSimulatorFramebufferStateStarting = 1, /** After the framebuffer has started, but before the first frame. */
  FBSimulatorFramebufferStateRunning = 2, /** After the framebuffer has started, but before the first frame. */
  FBSimulatorFramebufferStateTerminated = 3, /** After the framebuffer has terminated. */
};

static const NSInteger FBFramebufferLogFrameFrequency = 100;
// Timescale is in nanonseconds
static const CMTimeScale FBSimulatorFramebufferTimescale = 10E8;
static const CMTimeRoundingMethod FBSimulatorFramebufferRoundingMethod = kCMTimeRoundingMethod_Default;

@interface FBFramebuffer ()

@property (nonatomic, strong, readonly) SimDeviceFramebufferService *framebufferService;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<FBFramebufferDelegate> delegate;
@property (nonatomic, strong, readonly) dispatch_queue_t clientQueue;

@property (atomic, assign, readwrite) FBSimulatorFramebufferState state;
@property (atomic, assign, readwrite) CMTimebaseRef timebase;
@property (atomic, assign, readwrite) NSUInteger frameCount;
@property (atomic, assign, readwrite) CGSize size;

@end

@implementation FBFramebuffer

#pragma mark Initializers

+ (instancetype)withFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBSimulatorLaunchConfiguration *)launchConfiguration simulator:(FBSimulator *)simulator
{
  id<FBControlCoreLogger> logger = [simulator.logger withPrefix:[NSString stringWithFormat:@"%@:", simulator.udid]];
  NSMutableArray *sinks = [NSMutableArray array];
  BOOL useWindow = (launchConfiguration.options & FBSimulatorLaunchOptionsShowDebugWindow) == FBSimulatorLaunchOptionsShowDebugWindow;
  if (useWindow) {
    [sinks addObject:[FBFramebufferDebugWindow withName:@"Simulator"]];
  }

  FBFramebufferVideoConfiguration *videoConfiguration = [launchConfiguration.video withDiagnostic:simulator.diagnostics.video];
  FBFramebufferVideo *video = [FBFramebufferVideo withConfiguration:videoConfiguration logger:logger eventSink:simulator.eventSink];
  [sinks addObject:video];

  [sinks addObject:[FBFramebufferImage withDiagnostic:simulator.diagnostics.screenshot eventSink:simulator.eventSink]];

  id<FBFramebufferDelegate> delegate = [FBFramebufferCompositeDelegate withDelegates:[sinks copy]];
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBSimulatorControl.simulatorframebuffer", DISPATCH_QUEUE_SERIAL);

  return [[self alloc] initWithFramebufferService:framebufferService onQueue:queue video:video logger:[logger onQueue:queue] delegate:delegate];
}

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo *)video logger:(id<FBControlCoreLogger>)logger delegate:(id<FBFramebufferDelegate>)delegate
{
  NSParameterAssert(framebufferService);

  self = [super init];
  if (!self) {
    return nil;
  }

  _framebufferService = framebufferService;
  _video = video;
  _logger = logger;
  _delegate = delegate;

  _clientQueue = clientQueue;
  _state = FBSimulatorFramebufferStateNotStarted;
  _frameCount = 0;
  _size = CGSizeZero;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"%@ | Size %@ | Frame Count %ld",
    [FBFramebuffer stringFromFramebufferState:self.state],
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

#pragma mark Public

- (instancetype)startListeningInBackground;
{
  NSParameterAssert(NSThread.currentThread.isMainThread);
  NSParameterAssert(self.state == FBSimulatorFramebufferStateNotStarted);

  self.state = FBSimulatorFramebufferStateStarting;
  [self.framebufferService registerClient:self onQueue:self.clientQueue];
  [self.framebufferService resume];

  return self;
}

- (instancetype)stopListeningWithTeardownGroup:(dispatch_group_t)teardownGroup
{
  NSParameterAssert(NSThread.currentThread.isMainThread);
  NSParameterAssert(self.state != FBSimulatorFramebufferStateNotStarted);
  NSParameterAssert(self.state != FBSimulatorFramebufferStateTerminated);

  // Preserve the contract that the delegate methods are called on the client queue.
  // Use dispatch_sync so that adding entries to the group has occurred before this method returns.
  dispatch_sync(self.clientQueue, ^{
    [self framebufferDidBecomeInvalid:self error:nil teardownGroup:teardownGroup];
  });

  return self;
}

- (void)framebufferDidBecomeInvalid:(FBFramebuffer *)framebuffer error:(NSError *)error
{
  dispatch_group_t teardownGroup = dispatch_group_create();
  [self framebufferDidBecomeInvalid:framebuffer error:error teardownGroup:teardownGroup];
}

#pragma mark Client Callbacks from SimDeviceFramebufferService

- (void)framebufferService:(SimDeviceFramebufferService *)service didFailWithError:(NSError *)error
{
  [self framebufferDidBecomeInvalid:self error:error];
}

- (void)framebufferService:(SimDeviceFramebufferService *)service didRotateToAngle:(double)angle
{

}

- (void)framebufferService:(SimDeviceFramebufferService *)service didUpdateRegion:(CGRect)region ofBackingStore:(SimDeviceFramebufferBackingStore *)backingStore
{
  CGSize size = NSMakeSize(backingStore.pixelsWide, backingStore.pixelsHigh);
  self.size = size;
  [self frameUpdateWithImage:backingStore.image size:size];
  self.frameCount++;
}

#pragma mark Delegate Forwarding & Deduplicating

- (void)frameUpdateWithImage:(CGImageRef)image size:(CGSize)size
{
  if (self.state == FBSimulatorFramebufferStateStarting) {
    self.state = FBSimulatorFramebufferStateRunning;
    CMTimebaseRef timebase = NULL;
    CMTimebaseCreateWithMasterClock(
      kCFAllocatorDefault,
      CMClockGetHostTimeClock(),
      &timebase
    );
    NSAssert(timebase, @"Expected to be able to construct timebase");
    CMTimebaseSetRate(timebase, 1.0);
    self.timebase = timebase;
    [self.logger.info log:@"First Frame"];
  }
  if (self.state != FBSimulatorFramebufferStateRunning) {
    return;
  }

  FBFramebufferFrame *frame = [self frameFromCurrentTime:image size:size];
  [self.delegate framebuffer:self didUpdate:frame];
  if (self.frameCount % FBFramebufferLogFrameFrequency != 0) {
    return;
  }
  [self.logger.info logFormat:@"Frame Count %lu", self.frameCount];
}

- (void)framebufferDidBecomeInvalid:(FBFramebuffer *)framebuffer error:(NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
  if (self.state != FBSimulatorFramebufferStateStarting && self.state != FBSimulatorFramebufferStateRunning) {
    return;
  }

  self.state = FBSimulatorFramebufferStateTerminated;
  [self.framebufferService unregisterClient:self];
  [self.framebufferService suspend];
  CFRelease(self.timebase);
  self.timebase = nil;

  [self.delegate framebuffer:self didBecomeInvalidWithError:error teardownGroup:teardownGroup];
}

#pragma mark Private

- (FBFramebufferFrame *)frameFromCurrentTime:(CGImageRef)image size:(CGSize)size
{
  CMTime time = CMTimebaseGetTimeWithTimeScale(self.timebase, FBSimulatorFramebufferTimescale, FBSimulatorFramebufferRoundingMethod);
  return [[FBFramebufferFrame alloc] initWithTime:time timebase:self.timebase image:image count:self.frameCount size:size];
}

+ (NSString *)stringFromFramebufferState:(FBSimulatorFramebufferState)state
{
  switch (state) {
    case FBSimulatorFramebufferStateNotStarted:
      return @"Not Started";
    case FBSimulatorFramebufferStateStarting:
      return @"Starting";
    case FBSimulatorFramebufferStateRunning:
      return @"Running";
    case FBSimulatorFramebufferStateTerminated:
      return @"Terminated";
    default:
      return @"Unknown";
  }
}

@end

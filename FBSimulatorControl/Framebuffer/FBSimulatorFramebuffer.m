/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorFramebuffer.h"

#import <mach/exc.h>
#import <mach/mig.h>

#import <AppKit/AppKit.h>

#import <SimulatorKit/SimDeviceFramebufferBackingStore.h>
#import <SimulatorKit/SimDeviceFramebufferService.h>

#import "FBDiagnostic.h"
#import "FBFramebufferCompositeDelegate.h"
#import "FBFramebufferDebugWindow.h"
#import "FBFramebufferDelegate.h"
#import "FBFramebufferImage.h"
#import "FBFramebufferVideo.h"
#import "FBSimulator.h"
#import "FBSimulatorDiagnostics.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorLaunchConfiguration.h"
#import "FBSimulatorLogger.h"

/**
 Enumeration to keep track of internal state.
 */
typedef NS_ENUM(NSInteger, FBSimulatorFramebufferState) {
  FBSimulatorFramebufferStateNotStarted = 0, /** Before the framebuffer is 'listening'. */
  FBSimulatorFramebufferStateStarting = 1, /** After the framebuffer has started, but before the first frame. */
  FBSimulatorFramebufferStateRunning = 2, /** After the framebuffer has started, but before the first frame. */
  FBSimulatorFramebufferStateTerminated = 3, /** After the framebuffer has terminated. */
};

static const NSInteger FBFramebufferLogFrameFrequency = 100;

@interface FBSimulatorFramebuffer () <FBFramebufferDelegate>

@property (nonatomic, strong, readonly) SimDeviceFramebufferService *framebufferService;
@property (nonatomic, strong, readonly) id<FBSimulatorLogger> logger;
@property (nonatomic, strong, readonly) id<FBFramebufferDelegate> delegate;
@property (nonatomic, strong, readonly) dispatch_queue_t clientQueue;

@property (nonatomic, assign, readwrite) FBSimulatorFramebufferState state;
@property (atomic, assign, readwrite) NSUInteger frameCount;
@property (atomic, assign, readwrite) CGSize size;

@end

@implementation FBSimulatorFramebuffer

#pragma mark Initializers

+ (instancetype)withFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBSimulatorLaunchConfiguration *)launchConfiguration simulator:(FBSimulator *)simulator
{
  id<FBSimulatorLogger> logger = [simulator.logger withPrefix:[NSString stringWithFormat:@"%@:", simulator.udid]];
  NSMutableArray *sinks = [NSMutableArray array];
  BOOL useWindow = (launchConfiguration.options & FBSimulatorLaunchOptionsShowDebugWindow) == FBSimulatorLaunchOptionsShowDebugWindow;
  if (useWindow) {
    [sinks addObject:[FBFramebufferDebugWindow withName:@"Simulator"]];
  }

  BOOL recordVideo = (launchConfiguration.options & FBSimulatorLaunchOptionsRecordVideo) == FBSimulatorLaunchOptionsRecordVideo;
  if (recordVideo) {
    NSDecimalNumber *scaleNumber = [NSDecimalNumber decimalNumberWithString:launchConfiguration.scaleString];
    [sinks addObject:[FBFramebufferVideo withDiagnostic:simulator.diagnostics.video scale:scaleNumber.floatValue logger:logger eventSink:simulator.eventSink]];
  }
  [sinks addObject:[FBFramebufferImage withDiagnostic:simulator.diagnostics.screenshot eventSink:simulator.eventSink]];


  id<FBFramebufferDelegate> delegate = [FBFramebufferCompositeDelegate withDelegates:[sinks copy]];
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBSimulatorControl.simulatorframebuffer", DISPATCH_QUEUE_SERIAL);

  return [[self alloc] initWithFramebufferService:framebufferService onQueue:queue logger:[logger onQueue:queue] delegate:delegate];
}

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService onQueue:(dispatch_queue_t)clientQueue logger:(id<FBSimulatorLogger>)logger delegate:(id<FBFramebufferDelegate>)delegate
{
  NSParameterAssert(framebufferService);

  self = [super init];
  if (!self) {
    return nil;
  }

  _framebufferService = framebufferService;
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
    [FBSimulatorFramebuffer stringFromFramebufferState:self.state],
    NSStringFromSize(self.size),
    self.frameCount
  ];
}

#pragma mark FBJSONSerializationDescribeable Implementation

- (id)jsonSerializableRepresentation
{
  return @{
    @"size" : NSStringFromSize(self.size)
  };
}

#pragma mark Public

- (void)startListeningInBackground;
{
  NSParameterAssert(NSThread.currentThread.isMainThread);
  NSParameterAssert(self.state == FBSimulatorFramebufferStateNotStarted);

  self.state = FBSimulatorFramebufferStateStarting;
  [self.framebufferService registerClient:self onQueue:self.clientQueue];
  [self.framebufferService resume];
}

- (void)stopListening
{
  NSParameterAssert(NSThread.currentThread.isMainThread);
  NSParameterAssert(self.state != FBSimulatorFramebufferStateNotStarted);
  NSParameterAssert(self.state != FBSimulatorFramebufferStateTerminated);

  dispatch_sync(self.clientQueue, ^{
    [self framebufferDidBecomeInvalid:self error:nil];
  });
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
  [self framebufferDidUpdate:self withImage:backingStore.image count:self.frameCount size:NSMakeSize(backingStore.pixelsWide, backingStore.pixelsHigh)];
  self.frameCount++;
}

#pragma mark Internal Delegate Forwarding

- (void)framebufferDidUpdate:(FBSimulatorFramebuffer *)framebuffer withImage:(CGImageRef)image count:(NSUInteger)frameCount size:(CGSize)size
{
  if (self.state == FBSimulatorFramebufferStateStarting) {
    self.state = FBSimulatorFramebufferStateRunning;
    [self.logger.info log:@"First Frame"];
  }
  if (self.state != FBSimulatorFramebufferStateRunning) {
    return;
  }

  [self.delegate framebufferDidUpdate:framebuffer withImage:image count:frameCount size:size];

  if (frameCount % FBFramebufferLogFrameFrequency != 0) {
    return;
  }
  [self.logger.info logFormat:@"Frame Count %lu", frameCount];
}

- (void)framebufferDidBecomeInvalid:(FBSimulatorFramebuffer *)framebuffer error:(NSError *)error
{
  if (self.state != FBSimulatorFramebufferStateStarting && self.state != FBSimulatorFramebufferStateRunning) {
    return;
  }

  [self.framebufferService unregisterClient:self];
  [self.framebufferService suspend];

  [self.delegate framebufferDidBecomeInvalid:self error:error];
}

#pragma mark Private

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

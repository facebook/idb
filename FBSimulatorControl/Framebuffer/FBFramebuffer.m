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

#import <IOSurface/IOSurfaceBase.h>

#import "FBFramebufferCompositeDelegate.h"
#import "FBFramebufferDebugWindow.h"
#import "FBFramebufferDelegate.h"
#import "FBFramebufferFrame.h"
#import "FBFramebufferFrameGenerator.h"
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

@interface FBFramebuffer ()

@property (nonatomic, strong, readonly) SimDeviceFramebufferService *framebufferService;
@property (nonatomic, strong, readonly) FBFramebufferFrameGenerator *frameGenerator;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<FBFramebufferDelegate> delegate;
@property (nonatomic, strong, readonly) dispatch_queue_t clientQueue;

@property (atomic, assign, readwrite) FBSimulatorFramebufferState state;

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
  _frameGenerator = [FBFramebufferFrameGenerator generatorWithFramebuffer:self delegate:delegate logger:logger];

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"%@ | %@",
    [FBFramebuffer stringFromFramebufferState:self.state],
    self.frameGenerator
  ];
}

#pragma mark FBJSONSerializable Implementation

- (id)jsonSerializableRepresentation
{
  return self.frameGenerator.jsonSerializableRepresentation;
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
  if (self.state == FBSimulatorFramebufferStateStarting) {
    self.state = FBSimulatorFramebufferStateRunning;
    [self.frameGenerator firstFrameWithBackingStore:backingStore];
    return;
  }
  if (self.state != FBSimulatorFramebufferStateRunning) {
    return;
  }
  [self.frameGenerator backingStoreDidUpdate:backingStore];
}

- (void)setIOSurface:(IOSurfaceRef)surface
{
  [self.logger.info logFormat:@"Recieved IOSurface from Framebuffer Service %@", surface];
}

#pragma mark Delegate Forwarding & Deduplicating

- (void)framebufferDidBecomeInvalid:(FBFramebuffer *)framebuffer error:(NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
  if (self.state != FBSimulatorFramebufferStateStarting && self.state != FBSimulatorFramebufferStateRunning) {
    return;
  }

  self.state = FBSimulatorFramebufferStateTerminated;
  [self.framebufferService unregisterClient:self];
  [self.framebufferService suspend];
  [self.frameGenerator frameSteamEnded];

  [self.delegate framebuffer:self didBecomeInvalidWithError:error teardownGroup:teardownGroup];
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

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
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<FBFramebufferDelegate> delegate;
@property (nonatomic, strong, readonly) dispatch_queue_t clientQueue;

@property (atomic, assign, readwrite) FBSimulatorFramebufferState state;

@end

@interface FBFramebuffer_IOSurface : FBFramebuffer

@property (nonatomic, strong, readonly) FBFramebufferIOSurfaceFrameGenerator *frameGenerator;

@end

@interface FBFramebuffer_BackingStore : FBFramebuffer

@property (nonatomic, strong, readonly) FBFramebufferBackingStoreFrameGenerator *frameGenerator;

@end

@implementation FBFramebuffer

#pragma mark Initializers

+ (instancetype)withFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBSimulatorLaunchConfiguration *)launchConfiguration simulator:(FBSimulator *)simulator
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBSimulatorControl.FBFramebuffer.Client", DISPATCH_QUEUE_SERIAL);
  id<FBControlCoreLogger> logger = [[simulator.logger withPrefix:[NSString stringWithFormat:@"%@:", simulator.udid]] onQueue:queue];

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

  Class framebufferClass = FBControlCoreGlobalConfiguration.isXcode8OrGreater ? FBFramebuffer_IOSurface.class : FBFramebuffer_BackingStore.class;
  return [[framebufferClass alloc] initWithFramebufferService:framebufferService configuration:launchConfiguration onQueue:queue video:video delegate:delegate logger:logger];
}

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBSimulatorLaunchConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
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

  return self;
}

#pragma mark FBJSONSerializable Implementation

- (id)jsonSerializableRepresentation
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
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

#pragma mark Teardown

- (void)framebufferDidBecomeInvalid:(FBFramebuffer *)framebuffer error:(NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
  if (self.state != FBSimulatorFramebufferStateStarting && self.state != FBSimulatorFramebufferStateRunning) {
    return;
  }

  [self performTeardownWork];
  [self.delegate framebuffer:self didBecomeInvalidWithError:error teardownGroup:teardownGroup];
}

- (void)performTeardownWork
{
  self.state = FBSimulatorFramebufferStateTerminated;
  [self.framebufferService unregisterClient:self];
  [self.framebufferService suspend];
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

@implementation FBFramebuffer_IOSurface

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"IOSurface Framebuffer | %@ | %@",
    [FBFramebuffer stringFromFramebufferState:self.state],
    self.frameGenerator
  ];
}

#pragma mark FBJSONSerializable Implementation

- (id)jsonSerializableRepresentation
{
  return self.frameGenerator.jsonSerializableRepresentation;
}

#pragma mark Initializers

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBSimulatorLaunchConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithFramebufferService:framebufferService configuration:configuration onQueue:clientQueue video:video delegate:delegate logger:logger];
  if (!self) {
    return nil;
  }

  _frameGenerator = [FBFramebufferIOSurfaceFrameGenerator generatorWithFramebuffer:self scale:configuration.scaleValue delegate:delegate queue:clientQueue logger:logger];

  return self;
}

#pragma mark Client Callbacks from SimDeviceFramebufferService

- (void)framebufferService:(SimDeviceFramebufferService *)service didFailWithError:(NSError *)error
{
  [self framebufferDidBecomeInvalid:self error:error];
}

- (void)framebufferService:(SimDeviceFramebufferService *)service didRotateToAngle:(double)angle
{

}

- (void)setIOSurface:(IOSurfaceRef)surface
{
  // The client recieves a NULL surface, before recieving the first surface.
  if (self.state == FBSimulatorFramebufferStateStarting && surface == NULL) {
    return;
  }
  // This is the first surface that has been recieved.
  else if (self.state == FBSimulatorFramebufferStateStarting && surface != NULL) {
    self.state = FBSimulatorFramebufferStateRunning;
    [self.frameGenerator currentSurfaceChanged:surface];
  }
  NSParameterAssert(surface);
}

#pragma mark Teardown

- (void)performTeardownWork
{
  [super performTeardownWork];

  [self.frameGenerator frameSteamEnded];
}

@end

@implementation FBFramebuffer_BackingStore

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"SimDeviceFramebufferBackingStore Framebuffer | %@ | %@",
    [FBFramebuffer stringFromFramebufferState:self.state],
    self.frameGenerator
  ];
}

#pragma mark FBJSONSerializable Implementation

- (id)jsonSerializableRepresentation
{
  return self.frameGenerator.jsonSerializableRepresentation;
}

#pragma mark Initializers

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBSimulatorLaunchConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithFramebufferService:framebufferService configuration:configuration onQueue:clientQueue video:video delegate:delegate logger:logger];
  if (!self) {
    return nil;
  }

  _frameGenerator = [FBFramebufferBackingStoreFrameGenerator generatorWithFramebuffer:self scale:configuration.scaleValue delegate:delegate queue:clientQueue logger:logger];

  return self;
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
    [(FBFramebufferBackingStoreFrameGenerator *)self.frameGenerator firstFrameWithBackingStore:backingStore];
    return;
  }
  if (self.state != FBSimulatorFramebufferStateRunning) {
    return;
  }
  [self.frameGenerator backingStoreDidUpdate:backingStore];
}

#pragma mark Teardown

- (void)performTeardownWork
{
  [super performTeardownWork];

  [self.frameGenerator frameSteamEnded];
}

@end

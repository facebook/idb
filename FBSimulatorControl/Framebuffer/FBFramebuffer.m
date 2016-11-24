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

#import <SimulatorKit/SimDeviceFramebufferBackingStore+Removed.h>
#import <SimulatorKit/SimDeviceFramebufferService.h>
#import <SimulatorKit/SimDeviceFramebufferService+Removed.h>

#import <IOSurface/IOSurfaceBase.h>

#import "FBFramebufferCompositeDelegate.h"
#import "FBFramebufferDebugWindow.h"
#import "FBFramebufferDelegate.h"
#import "FBFramebufferFrame.h"
#import "FBFramebufferFrameGenerator.h"
#import "FBFramebufferImage.h"
#import "FBFramebufferVideo.h"
#import "FBFramebufferConfiguration.h"
#import "FBSimulator.h"
#import "FBSimulatorDiagnostics.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBSimulatorError.h"

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

@property (nonatomic, strong, nullable, readonly) SimDeviceFramebufferService *framebufferService;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<FBFramebufferDelegate> delegate;
@property (nonatomic, strong, readonly) dispatch_queue_t clientQueue;

@property (atomic, assign, readwrite) FBSimulatorFramebufferState state;

@end

@interface FBFramebuffer_FrameGenerator : FBFramebuffer

@property (nonatomic, strong, readonly) FBFramebufferFrameGenerator *frameGenerator;

@end

@interface FBFramebuffer_FrameGenerator_IOSurface : FBFramebuffer

@property (nonatomic, strong, readonly) FBFramebufferIOSurfaceFrameGenerator *ioSurfaceGenerator;

@end

@interface FBFramebuffer_FrameGenerator_BackingStore : FBFramebuffer

@property (nonatomic, strong, readonly) FBFramebufferBackingStoreFrameGenerator *backingStoreGenerator;

@end

@implementation FBFramebuffer

#pragma mark Initializers

+ (instancetype)withFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBFramebufferConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBSimulatorControl.FBFramebuffer.Client", DISPATCH_QUEUE_SERIAL);
  id<FBControlCoreLogger> logger = [[simulator.logger withPrefix:[NSString stringWithFormat:@"%@:", simulator.udid]] onQueue:queue];

  NSMutableArray *sinks = [NSMutableArray array];
  if (configuration.showDebugWindow) {
    [sinks addObject:[FBFramebufferDebugWindow withName:@"Simulator"]];
  }

  FBFramebufferConfiguration *videoConfiguration = [configuration withDiagnostic:simulator.diagnostics.video];
  FBFramebufferVideo *video = [FBFramebufferVideo withConfiguration:videoConfiguration logger:logger eventSink:simulator.eventSink];
  [sinks addObject:video];

  [sinks addObject:[FBFramebufferImage withDiagnostic:simulator.diagnostics.screenshot eventSink:simulator.eventSink]];

  id<FBFramebufferDelegate> delegate = [FBFramebufferCompositeDelegate withDelegates:[sinks copy]];

  Class framebufferClass = FBControlCoreGlobalConfiguration.isXcode8OrGreater ? FBFramebuffer_FrameGenerator_IOSurface.class : FBFramebuffer_FrameGenerator_BackingStore.class;
  return [[framebufferClass alloc] initWithFramebufferService:framebufferService configuration:configuration onQueue:queue video:video delegate:delegate logger:logger];
}

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
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

  // Only call invalidate if the selector exists.
  if ([self.framebufferService respondsToSelector:@selector(invalidate)]) {
    // The call to this method has been dropped in Xcode 8.1, but exists in Xcode 8.0
    // Don't call it on Xcode 8.1
    if ([FBControlCoreGlobalConfiguration.xcodeVersionNumber isLessThan:[NSDecimalNumber decimalNumberWithString:@"8.1"]]) {
      [self.framebufferService invalidate];
    }
  }

  // Release the Service by removing the reference.
  _framebufferService = nil;
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

@implementation FBFramebuffer_FrameGenerator

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Framebuffer | %@ | %@",
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

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithFramebufferService:framebufferService configuration:configuration onQueue:clientQueue video:video delegate:delegate logger:logger];
  if (!self) {
    return nil;
  }

  return self;
}

#pragma mark Properties

- (FBFramebufferFrameGenerator *)frameGenerator
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark Client Callbacks from SimDeviceFramebufferService

- (void)framebufferService:(SimDeviceFramebufferService *)service didFailWithError:(NSError *)error
{
  [self framebufferDidBecomeInvalid:self error:error];
}

- (void)framebufferService:(SimDeviceFramebufferService *)service didRotateToAngle:(double)angle
{

}

#pragma mark Teardown

- (void)performTeardownWork
{
  [super performTeardownWork];

  [self.frameGenerator frameSteamEnded];
}

@end

@implementation FBFramebuffer_FrameGenerator_BackingStore

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithFramebufferService:framebufferService configuration:configuration onQueue:clientQueue video:video delegate:delegate logger:logger];
  if (!self) {
    return nil;
  }

  _backingStoreGenerator = [FBFramebufferBackingStoreFrameGenerator generatorWithFramebuffer:self scale:NSDecimalNumber.one delegate:delegate queue:clientQueue logger:logger];
  return self;
}

- (FBFramebufferFrameGenerator *)frameGenerator
{
  return self.backingStoreGenerator;
}

- (void)framebufferService:(SimDeviceFramebufferService *)service didUpdateRegion:(CGRect)region ofBackingStore:(SimDeviceFramebufferBackingStore *)backingStore
{
  // We recieve the backing store on the first surface.
  if (self.state == FBSimulatorFramebufferStateStarting) {
    self.state = FBSimulatorFramebufferStateRunning;
    [self.backingStoreGenerator backingStoreDidUpdate:backingStore];
  }
}

@end

@implementation FBFramebuffer_FrameGenerator_IOSurface

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithFramebufferService:framebufferService configuration:configuration onQueue:clientQueue video:video delegate:delegate logger:logger];
  if (!self) {
    return nil;
  }

  _ioSurfaceGenerator = [FBFramebufferIOSurfaceFrameGenerator generatorWithFramebuffer:self scale:NSDecimalNumber.one delegate:delegate queue:clientQueue logger:logger];
  return self;
}

- (FBFramebufferFrameGenerator *)frameGenerator
{
  return self.ioSurfaceGenerator;
}

- (void)setIOSurface:(IOSurfaceRef)surface
{
  NSParameterAssert(surface);
  // The client recieves a NULL surface, before recieving the first surface.
  if (self.state == FBSimulatorFramebufferStateStarting && surface == NULL) {
    return;
  }
  // This is the first surface that has been recieved.
  else if (self.state == FBSimulatorFramebufferStateStarting && surface != NULL) {
    self.state = FBSimulatorFramebufferStateRunning;
    [self.ioSurfaceGenerator currentSurfaceChanged:surface];
  }
}

@end

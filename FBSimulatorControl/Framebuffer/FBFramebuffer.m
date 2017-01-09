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

#import <objc/runtime.h>

#import <Cocoa/Cocoa.h>

#import <FBControlCore/FBControlCore.h>

#import <SimulatorKit/SimDeviceFramebufferBackingStore+Removed.h>
#import <SimulatorKit/SimDeviceFramebufferService.h>
#import <SimulatorKit/SimDeviceFramebufferService+Removed.h>
#import <SimulatorKit/SimDeviceIOPortConsumer-Protocol.h>
#import <SimulatorKit/SimDisplayVideoWriter.h>

#import <IOSurface/IOSurfaceBase.h>
#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceIO.h>
#import <CoreSimulator/SimDeviceIOClient.h>

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
#import "FBFramebufferSurfaceClient.h"

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

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<FBFramebufferDelegate> delegate;
@property (nonatomic, strong, readonly) dispatch_queue_t clientQueue;

@property (atomic, assign, readwrite) FBSimulatorFramebufferState state;

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger;

@end

@interface FBFramebuffer_FrameGenerator : FBFramebuffer

@property (nonatomic, strong, readonly) FBFramebufferFrameGenerator *frameGenerator;

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_BuiltIn *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger;

@end

@interface FBFramebuffer_FrameGenerator_IOSurface : FBFramebuffer_FrameGenerator

@property (nonatomic, strong, readonly) FBFramebufferIOSurfaceFrameGenerator *ioSurfaceGenerator;
@property (nonatomic, strong, readonly) FBFramebufferSurfaceClient *surfaceClient;

- (instancetype)initWithSurfaceClient:(FBFramebufferSurfaceClient *)surfaceClient configuration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_BuiltIn *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger;

@end

@interface FBFramebuffer_FrameGenerator_BackingStore : FBFramebuffer_FrameGenerator

@property (nonatomic, strong, nullable, readonly) SimDeviceFramebufferService *framebufferService;
@property (nonatomic, strong, readonly) FBFramebufferBackingStoreFrameGenerator *backingStoreGenerator;

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_BuiltIn *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger;

@end

@interface FBFramebuffer_SimulatorKit : FBFramebuffer

@property (nonatomic, strong, readonly) SimDeviceIOClient *ioClient;
@property (nonatomic, strong, readonly) FBFramebufferVideo_SimulatorKit *simulatorKitVideo;

- (instancetype)initWithIOClient:(SimDeviceIOClient *)ioClient configuration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_SimulatorKit *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger;

@end

@implementation FBFramebuffer

#pragma mark Initializers

+ (dispatch_queue_t)createClientQueue
{
  return dispatch_queue_create("com.facebook.fbsimulatorcontrol.framebuffer.client", DISPATCH_QUEUE_SERIAL);
}

+ (id<FBControlCoreLogger>)loggerForSimulator:(FBSimulator *)simulator queue:(dispatch_queue_t)queue
{
  return [[simulator.logger withPrefix:[NSString stringWithFormat:@"%@:", simulator.udid]] onQueue:queue];
}

+ (id<FBFramebufferDelegate>)delegateForSimulator:(FBSimulator *)simulator configuration:(FBFramebufferConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger videoOut:(FBFramebufferVideo_BuiltIn **)videoOut
{
  NSMutableArray<id<FBFramebufferDelegate>> *sinks = [NSMutableArray array];
  FBFramebufferConfiguration *videoConfiguration = [configuration withDiagnostic:simulator.simulatorDiagnostics.video];
  FBFramebufferVideo_BuiltIn *video = [FBFramebufferVideo_BuiltIn withConfiguration:videoConfiguration logger:logger eventSink:simulator.eventSink];
  [sinks addObject:video];
  [sinks addObject:[FBFramebufferImage withDiagnostic:simulator.simulatorDiagnostics.screenshot eventSink:simulator.eventSink]];
  if (configuration.showDebugWindow) {
    [sinks addObject:[FBFramebufferDebugWindow withName:@"Simulator"]];
  }
  id<FBFramebufferDelegate> delegate = [FBFramebufferCompositeDelegate withDelegates:[sinks copy]];
  if (videoOut) {
    *videoOut = video;
  }
  return delegate;
}

+ (instancetype)withFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBFramebufferConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  dispatch_queue_t queue = self.createClientQueue;
  id<FBControlCoreLogger> logger = [self loggerForSimulator:simulator queue:queue];

  FBFramebufferVideo_BuiltIn *video = nil;
  id<FBFramebufferDelegate> delegate = [self delegateForSimulator:simulator configuration:configuration logger:logger videoOut:&video];

  if (FBControlCoreGlobalConfiguration.isXcode8OrGreater) {
    FBFramebufferSurfaceClient *surfaceClient = [FBFramebufferSurfaceClient clientForFramebufferService:framebufferService clientQueue:self.createClientQueue];
    return [[FBFramebuffer_FrameGenerator_IOSurface alloc] initWithSurfaceClient:surfaceClient configuration:configuration onQueue:queue video:video delegate:delegate logger:logger];
  }
  return [[FBFramebuffer_FrameGenerator_BackingStore alloc] initWithFramebufferService:framebufferService configuration:configuration onQueue:queue video:video delegate:delegate logger:logger];
}

+ (instancetype)withIOClient:(SimDeviceIOClient *)ioClient configuration:(FBFramebufferConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  dispatch_queue_t queue = self.createClientQueue;
  id<FBControlCoreLogger> logger = [self loggerForSimulator:simulator queue:queue];

  FBFramebufferConfiguration *videoConfiguration = [configuration withDiagnostic:simulator.simulatorDiagnostics.video];
  // If we support the Xcode 8.1 SimDisplayVideoWriter, we can construct and use it here.
  if (FBFramebufferVideo_SimulatorKit.isSupported) {
    FBFramebufferVideo_SimulatorKit *video = [FBFramebufferVideo_SimulatorKit withConfiguration:videoConfiguration ioClient:ioClient logger:logger eventSink:simulator.eventSink];
    id<FBFramebufferDelegate> delegate = [FBFramebufferCompositeDelegate withDelegates:@[]];
    return [[FBFramebuffer_SimulatorKit alloc] initWithIOClient:ioClient configuration:configuration onQueue:queue video:video delegate:delegate logger:logger];
  }
  // Otherwise we have to use the built-in frame generation.
  FBFramebufferVideo_BuiltIn *video = nil;
  id<FBFramebufferDelegate> delegate = [self delegateForSimulator:simulator configuration:configuration logger:logger videoOut:&video];
  FBFramebufferSurfaceClient *surfaceClient = [FBFramebufferSurfaceClient clientForIOClient:ioClient clientQueue:queue];
  return [[FBFramebuffer_FrameGenerator_IOSurface alloc] initWithSurfaceClient:surfaceClient configuration:configuration onQueue:queue video:video delegate:delegate logger:logger];
}

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

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

- (id<FBFramebufferVideo>)video
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark Public

- (instancetype)startListeningInBackground
{
  NSParameterAssert(NSThread.currentThread.isMainThread);
  NSParameterAssert(self.state == FBSimulatorFramebufferStateNotStarted);
  self.state = FBSimulatorFramebufferStateStarting;

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

@synthesize video = _video;

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

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_BuiltIn *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithConfiguration:configuration onQueue:clientQueue delegate:delegate logger:logger];
  if (!self) {
    return nil;
  }

  _video = video;

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

- (instancetype)initWithFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_BuiltIn *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithConfiguration:configuration onQueue:clientQueue video:video delegate:delegate logger:logger];
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

- (instancetype)startListeningInBackground
{
  [super startListeningInBackground];
  [self.framebufferService registerClient:self onQueue:self.clientQueue];
  [self.framebufferService resume];
  return self;
}

- (instancetype)stopListeningWithTeardownGroup:(dispatch_group_t)teardownGroup
{
  [super stopListeningWithTeardownGroup:teardownGroup];
  [FBFramebufferSurfaceClient detachFromFramebufferService:self.framebufferService];
  _framebufferService = nil;
  return self;
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

- (instancetype)initWithSurfaceClient:(FBFramebufferSurfaceClient *)surfaceClient configuration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_BuiltIn *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithConfiguration:configuration onQueue:clientQueue video:video delegate:delegate logger:logger];
  if (!self) {
    return nil;
  }

  _surfaceClient = surfaceClient;
  _ioSurfaceGenerator = [FBFramebufferIOSurfaceFrameGenerator generatorWithFramebuffer:self scale:NSDecimalNumber.one delegate:delegate queue:clientQueue logger:logger];

  return self;
}

- (FBFramebufferFrameGenerator *)frameGenerator
{
  return self.ioSurfaceGenerator;
}

#pragma mark Private

- (instancetype)startListeningInBackground
{
  [super startListeningInBackground];

  [self.surfaceClient obtainSurface:^(IOSurfaceRef surface) {
    [self ioSurfaceUpdated:surface];
  }];
  return self;
}

- (instancetype)stopListeningWithTeardownGroup:(dispatch_group_t)teardownGroup
{
  [super stopListeningWithTeardownGroup:teardownGroup];

  [self.surfaceClient detach];
  return self;
}

- (void)ioSurfaceUpdated:(IOSurfaceRef)surface
{
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

@implementation FBFramebuffer_SimulatorKit

- (instancetype)initWithIOClient:(SimDeviceIOClient *)ioClient configuration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_SimulatorKit *)video delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithConfiguration:configuration onQueue:clientQueue delegate:delegate logger:logger];
  if (!self) {
    return nil;
  }

  _ioClient = ioClient;
  _simulatorKitVideo = video;

  return self;
}

- (id)jsonSerializableRepresentation
{
  return @{
    @"io_client" : self.ioClient.description,
  };
}

- (id<FBFramebufferVideo>)video
{
  return self.simulatorKitVideo;
}

- (instancetype)startListeningInBackground
{
  return self;
}

- (instancetype)stopListeningWithTeardownGroup:(dispatch_group_t)teardownGroup
{
  return self;
}

@end

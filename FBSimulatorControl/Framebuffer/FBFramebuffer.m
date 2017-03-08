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

#import "FBFramebufferDebugWindow.h"
#import "FBFramebufferFrameSink.h"
#import "FBFramebufferFrame.h"
#import "FBFramebufferFrameGenerator.h"
#import "FBFramebufferImage.h"
#import "FBFramebufferVideo.h"
#import "FBFramebufferRenderable.h"
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

@property (nonatomic, strong, readonly) dispatch_queue_t clientQueue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@property (atomic, assign, readwrite) FBSimulatorFramebufferState state;

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(id<FBFramebufferVideo>)video image:(id<FBFramebufferImage>)image logger:(id<FBControlCoreLogger>)logger;

@end

@interface FBFramebuffer_FrameGenerator : FBFramebuffer

@property (nonatomic, strong, readonly) FBFramebufferFrameGenerator *frameGenerator;

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_BuiltIn *)video image:(id<FBFramebufferImage>)image frameSink:(id<FBFramebufferFrameSink>)frameSink logger:(id<FBControlCoreLogger>)logger;

@end

@interface FBFramebuffer_FrameGenerator_IOSurface : FBFramebuffer_FrameGenerator <FBFramebufferRenderableConsumer>

@property (nonatomic, strong, readonly) FBFramebufferIOSurfaceFrameGenerator *ioSurfaceGenerator;
@property (nonatomic, strong, readonly) FBFramebufferRenderable *renderable;

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_BuiltIn *)video image:(id<FBFramebufferImage>)image frameSink:(id<FBFramebufferFrameSink>)frameSink renderable:(FBFramebufferRenderable *)renderable logger:(id<FBControlCoreLogger>)logger;

@end

@interface FBFramebuffer_FrameGenerator_BackingStore : FBFramebuffer_FrameGenerator

@property (nonatomic, strong, nullable, readonly) SimDeviceFramebufferService *framebufferService;
@property (nonatomic, strong, readonly) FBFramebufferBackingStoreFrameGenerator *backingStoreGenerator;

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_BuiltIn *)video image:(id<FBFramebufferImage>)image frameSink:(id<FBFramebufferFrameSink>)frameSink framebufferService:(SimDeviceFramebufferService *)framebufferService logger:(id<FBControlCoreLogger>)logger;

@end

@interface FBFramebuffer_SimulatorKit : FBFramebuffer

@property (nonatomic, strong, readonly) FBFramebufferRenderable *renderable;

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_SimulatorKit *)video image:(id<FBFramebufferImage>)image renderable:(FBFramebufferRenderable *)renderable logger:(id<FBControlCoreLogger>)logger;

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

+ (id<FBFramebufferFrameSink>)frameSinkForSimulator:(FBSimulator *)simulator configuration:(FBFramebufferConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger videoOut:(FBFramebufferVideo_BuiltIn **)videoOut imageOut:(FBFramebufferImage_FrameSink **)imageOut;
{
  NSMutableArray<id<FBFramebufferFrameSink>> *frameSinks = [NSMutableArray array];
  FBFramebufferConfiguration *videoConfiguration = [configuration withDiagnostic:simulator.simulatorDiagnostics.video];
  FBFramebufferVideo_BuiltIn *video = [FBFramebufferVideo_BuiltIn withConfiguration:videoConfiguration logger:logger eventSink:simulator.eventSink];
  FBFramebufferImage_FrameSink *image = [FBFramebufferImage_FrameSink withDiagnostic:simulator.simulatorDiagnostics.screenshot eventSink:simulator.eventSink];
  [frameSinks addObject:video];
  [frameSinks addObject:image];
  if (configuration.showDebugWindow) {
    [frameSinks addObject:[FBFramebufferDebugWindow withName:@"Simulator"]];
  }
  id<FBFramebufferFrameSink> delegate = [FBFramebufferCompositeFrameSink withSinks:[frameSinks copy]];
  if (videoOut) {
    *videoOut = video;
  }
  if (imageOut) {
    *imageOut = image;
  }
  return delegate;
}

+ (instancetype)framebufferWithService:(SimDeviceFramebufferService *)framebufferService configuration:(FBFramebufferConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  dispatch_queue_t queue = self.createClientQueue;
  id<FBControlCoreLogger> logger = [self loggerForSimulator:simulator queue:queue];

  FBFramebufferVideo_BuiltIn *video = nil;
  FBFramebufferImage_FrameSink *image = nil;
  id<FBFramebufferFrameSink> frameSink = [self frameSinkForSimulator:simulator configuration:configuration logger:logger videoOut:&video imageOut:&image];

  if (FBControlCoreGlobalConfiguration.isXcode8OrGreater) {
    FBFramebufferRenderable *renderable = [FBFramebufferRenderable mainScreenRenderableForFramebufferService:framebufferService clientQueue:self.createClientQueue];
    return [[FBFramebuffer_FrameGenerator_IOSurface alloc] initWithConfiguration:configuration onQueue:queue video:video image:image frameSink:frameSink renderable:renderable logger:logger];
  }
  return [[FBFramebuffer_FrameGenerator_BackingStore alloc] initWithConfiguration:configuration onQueue:queue video:video image:image frameSink:frameSink framebufferService:framebufferService logger:logger];
}

+ (instancetype)framebufferWithRenderable:(FBFramebufferRenderable *)renderable configuration:(FBFramebufferConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  dispatch_queue_t queue = self.createClientQueue;
  id<FBControlCoreLogger> logger = [self loggerForSimulator:simulator queue:queue];

  FBFramebufferConfiguration *videoConfiguration = [configuration withDiagnostic:simulator.simulatorDiagnostics.video];
  // If we support the Xcode 8.1 SimDisplayVideoWriter, we can construct and use it here.
  if (FBFramebufferVideo_SimulatorKit.isSupported) {
    FBFramebufferVideo_SimulatorKit *video = [FBFramebufferVideo_SimulatorKit withConfiguration:videoConfiguration renderable:renderable logger:logger eventSink:simulator.eventSink];
    FBFramebufferImage_Surface *image = [FBFramebufferImage_Surface withDiagnostic:simulator.simulatorDiagnostics.screenshot renderable:renderable eventSink:simulator.eventSink];
    return [[FBFramebuffer_SimulatorKit alloc] initWithConfiguration:configuration onQueue:queue video:video image:image renderable:renderable logger:logger];
  }
  // Otherwise we have to use the built-in frame generation.
  FBFramebufferVideo_BuiltIn *video = nil;
  FBFramebufferImage_FrameSink *image = nil;
  id<FBFramebufferFrameSink> frameSink = [self frameSinkForSimulator:simulator configuration:configuration logger:logger videoOut:&video imageOut:&image];
  return [[FBFramebuffer_FrameGenerator_IOSurface alloc] initWithConfiguration:videoConfiguration onQueue:queue video:video image:image frameSink:frameSink renderable:renderable logger:logger];
}

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(id<FBFramebufferVideo>)video image:(id<FBFramebufferImage>)image logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logger = logger;
  _clientQueue = clientQueue;
  _video = video;
  _image = image;
  _state = FBSimulatorFramebufferStateNotStarted;

  return self;
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

#pragma mark Teardown

- (void)framebufferDidBecomeInvalid:(FBFramebuffer *)framebuffer error:(nullable NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
  if (self.state != FBSimulatorFramebufferStateStarting && self.state != FBSimulatorFramebufferStateRunning) {
    return;
  }

  [self performTeardownWork];
}

- (void)framebufferDidBecomeInvalid:(FBFramebuffer *)framebuffer error:(NSError *)error
{
  dispatch_group_t teardownGroup = dispatch_group_create();
  [self framebufferDidBecomeInvalid:framebuffer error:error teardownGroup:teardownGroup];
}

- (void)performTeardownWork
{
  self.state = FBSimulatorFramebufferStateTerminated;
}

#pragma mark FBJSONSerializable Implementation

- (id)jsonSerializableRepresentation
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
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


#pragma mark Initializers

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_BuiltIn *)video image:(FBFramebufferImage_FrameSink *)image frameSink:(id<FBFramebufferFrameSink>)frameSink logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithConfiguration:configuration onQueue:clientQueue video:video image:image logger:logger];
  if (!self) {
    return nil;
  }
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

#pragma mark Private

- (void)framebufferDidBecomeInvalid:(FBFramebuffer *)framebuffer error:(nullable NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
  [super framebufferDidBecomeInvalid:framebuffer error:error teardownGroup:teardownGroup];

  [self.frameGenerator frameSteamEndedWithTeardownGroup:teardownGroup error:error];
}

- (FBFramebufferFrameGenerator *)frameGenerator
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

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

@end

@implementation FBFramebuffer_FrameGenerator_BackingStore

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_BuiltIn *)video image:(id<FBFramebufferImage>)image frameSink:(id<FBFramebufferFrameSink>)frameSink framebufferService:(SimDeviceFramebufferService *)framebufferService logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithConfiguration:configuration onQueue:clientQueue video:video image:image frameSink:frameSink logger:logger];
  if (!self) {
    return nil;
  }

  _framebufferService = framebufferService;
  _backingStoreGenerator = [FBFramebufferBackingStoreFrameGenerator generatorWithScale:NSDecimalNumber.one sink:frameSink queue:clientQueue logger:logger];

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
  [self.framebufferService unregisterClient:self];
  _framebufferService = nil;
  return self;
}

- (void)framebufferService:(SimDeviceFramebufferService *)service didUpdateRegion:(CGRect)region ofBackingStore:(SimDeviceFramebufferBackingStore *)backingStore
{
  // We recieve the backing store on the first surface.
  if (self.state == FBSimulatorFramebufferStateStarting) {
    self.state = FBSimulatorFramebufferStateRunning;
    [self.backingStoreGenerator firstFrameWithBackingStore:backingStore];
  } else if (self.state == FBSimulatorFramebufferStateRunning) {
    [self.backingStoreGenerator backingStoreDidUpdate:backingStore];
  }
}

@end

@implementation FBFramebuffer_FrameGenerator_IOSurface

#pragma mark Initializers

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_BuiltIn *)video image:(FBFramebufferImage_FrameSink *)image frameSink:(id<FBFramebufferFrameSink>)frameSink renderable:(FBFramebufferRenderable *)renderable logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithConfiguration:configuration onQueue:clientQueue video:video image:image frameSink:frameSink logger:logger];
  if (!self) {
    return nil;
  }

  _renderable = renderable;
  _ioSurfaceGenerator = [FBFramebufferIOSurfaceFrameGenerator generatorWithScale:NSDecimalNumber.one sink:frameSink queue:clientQueue logger:logger];

  return self;
}

#pragma mark Public

- (FBFramebufferFrameGenerator *)frameGenerator
{
  return self.ioSurfaceGenerator;
}

- (instancetype)startListeningInBackground
{
  [super startListeningInBackground];

  [self.renderable attachConsumer:self];
  return self;
}

- (instancetype)stopListeningWithTeardownGroup:(dispatch_group_t)teardownGroup
{
  [super stopListeningWithTeardownGroup:teardownGroup];

  [self.renderable detachConsumer:self];
  return self;
}

#pragma mark FBFramebufferRenderableConsumer

- (void)didChangeIOSurface:(IOSurfaceRef)surface
{
  // The client recieves a NULL surface, before recieving the first surface.
  if (self.state == FBSimulatorFramebufferStateStarting && surface == NULL) {
    return;
  }
  // This is the first surface that has been recieved.
  else if (self.state == FBSimulatorFramebufferStateStarting && surface != NULL) {
    self.state = FBSimulatorFramebufferStateRunning;
    [self.ioSurfaceGenerator didChangeIOSurface:surface];
  }
}

- (void)didRecieveDamageRect:(CGRect)rect
{

}

- (NSString *)consumerIdentifier
{
  return self.ioSurfaceGenerator.consumerIdentifier;
}

@end

@implementation FBFramebuffer_SimulatorKit

#pragma mark Initializers

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration onQueue:(dispatch_queue_t)clientQueue video:(FBFramebufferVideo_SimulatorKit *)video image:(FBFramebufferImage_Surface *)image renderable:(FBFramebufferRenderable *)renderable logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithConfiguration:configuration onQueue:clientQueue video:video image:image logger:logger];
  if (!self) {
    return nil;
  }

  _renderable = renderable;

  return self;
}

#pragma mark Public

- (instancetype)startListeningInBackground
{
  return self;
}

- (instancetype)stopListeningWithTeardownGroup:(dispatch_group_t)teardownGroup
{
  return self;
}

#pragma mark FBJSONSerializable Implementation

- (id)jsonSerializableRepresentation
{
  return @{
    @"io_client" : self.renderable.description,
  };
}

@end

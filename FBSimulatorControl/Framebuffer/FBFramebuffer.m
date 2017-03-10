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

#import "FBFramebufferFrame.h"
#import "FBFramebufferFrameGenerator.h"
#import "FBFramebufferImage.h"
#import "FBFramebufferVideo.h"
#import "FBFramebufferSurface.h"
#import "FBFramebufferConfiguration.h"
#import "FBSimulator.h"
#import "FBSimulatorDiagnostics.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBSimulatorError.h"
#import "FBVideoEncoderConfiguration.h"

@interface FBFramebuffer ()

@property (nonatomic, strong, readonly) FBFramebufferConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) FBFramebufferFrameGenerator *frameGenerator;

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration eventSink:(id<FBSimulatorEventSink>)eventSink frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator logger:(id<FBControlCoreLogger>)logger;

@end

@interface FBFramebuffer_FramebufferService : FBFramebuffer

@end

@interface FBFramebuffer_IOSurface : FBFramebuffer

@property (nonatomic, strong, readonly) FBFramebufferIOSurfaceFrameGenerator *ioSurfaceGenerator;
@property (nonatomic, strong, readonly) FBFramebufferSurface *surface;

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration eventSink:(id<FBSimulatorEventSink>)eventSink frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator surface:(FBFramebufferSurface *)surface logger:(id<FBControlCoreLogger>)logger;

@end

@implementation FBFramebuffer

@synthesize image = _image;
@synthesize video = _video;

#pragma mark Initializers

+ (dispatch_queue_t)createClientQueue
{
  return dispatch_queue_create("com.facebook.fbsimulatorcontrol.framebuffer.client", DISPATCH_QUEUE_SERIAL);
}

+ (id<FBControlCoreLogger>)loggerForSimulator:(FBSimulator *)simulator queue:(dispatch_queue_t)queue
{
  return [[simulator.logger withPrefix:[NSString stringWithFormat:@"%@:", simulator.udid]] onQueue:queue];
}

+ (instancetype)framebufferWithService:(SimDeviceFramebufferService *)framebufferService configuration:(FBFramebufferConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  dispatch_queue_t queue = self.createClientQueue;
  id<FBControlCoreLogger> logger = [self loggerForSimulator:simulator queue:queue];

  if (FBControlCoreGlobalConfiguration.isXcode8OrGreater) {
    FBFramebufferSurface *surface = [FBFramebufferSurface
      mainScreenSurfaceForFramebufferService:framebufferService
      clientQueue:queue];
    FBFramebufferFrameGenerator *frameGenerator = [FBFramebufferIOSurfaceFrameGenerator
      generatorWithRenderable:surface
      scale:configuration.scaleValue
      queue:queue
      logger:logger];

    return [[FBFramebuffer_IOSurface alloc] initWithConfiguration:configuration eventSink:simulator.eventSink frameGenerator:frameGenerator surface:surface logger:logger];
  }
  FBFramebufferBackingStoreFrameGenerator *frameGenerator = [FBFramebufferBackingStoreFrameGenerator generatorWithFramebufferService:framebufferService scale:configuration.scaleValue queue:queue logger:logger];
  return [[FBFramebuffer_FramebufferService alloc] initWithConfiguration:configuration eventSink:simulator.eventSink frameGenerator:frameGenerator logger:logger];
}

+ (instancetype)framebufferWithRenderable:(FBFramebufferSurface *)surface configuration:(FBFramebufferConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  dispatch_queue_t queue = self.createClientQueue;
  id<FBControlCoreLogger> logger = [self loggerForSimulator:simulator queue:queue];

  // Otherwise we have to use the built-in frame generation.
  FBFramebufferFrameGenerator *frameGenerator = [FBFramebufferIOSurfaceFrameGenerator
    generatorWithRenderable:surface
    scale:configuration.scaleValue
    queue:queue
    logger:logger];
  return [[FBFramebuffer_IOSurface alloc] initWithConfiguration:configuration eventSink:simulator.eventSink frameGenerator:frameGenerator surface:surface logger:logger];
}

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration eventSink:(id<FBSimulatorEventSink>)eventSink frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _eventSink = eventSink;
  _frameGenerator = frameGenerator;
  _logger = logger;

  return self;
}

#pragma mark Public

- (void)teardownWithGroup:(dispatch_group_t)teardownGroup
{
  NSParameterAssert(NSThread.currentThread.isMainThread);
  [self.frameGenerator teardownWithGroup:teardownGroup];
}

- (void)attachFrameSink:(id<FBFramebufferFrameSink>)frameSink
{
  NSParameterAssert(frameSink);
  [self.frameGenerator attachSink:frameSink];
}

- (void)detachFrameSink:(id<FBFramebufferFrameSink>)frameSink
{
  NSParameterAssert(frameSink);
  [self.frameGenerator detachSink:frameSink];
}

- (BOOL)attachSurfaceConsumer:(id<FBFramebufferSurfaceConsumer>)consumer error:(NSError **)error
{
  return [[FBSimulatorError
    describeFormat:@"%@ a Surface Consumer is not supported for class %@", NSStringFromSelector(_cmd), NSStringFromClass(self.class)]
    failBool:error];
}

- (BOOL)detachSurfaceConsumer:(id<FBFramebufferSurfaceConsumer>)consumer error:(NSError **)error
{
  return [[FBSimulatorError
    describeFormat:@"%@ a Surface Consumer is not supported for class %@", NSStringFromSelector(_cmd), NSStringFromClass(self.class)]
    failBool:error];
}

#pragma mark Properties

- (id<FBFramebufferImage>)image
{
  if (!_image) {
    _image = [self createImage];
  }
  return _image;
}

- (id<FBFramebufferVideo>)video
{
  if (!_video) {
    _video = [self createVideo];
  }
  return _video;
}

- (id<FBFramebufferImage>)createImage
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id<FBFramebufferVideo>)createVideo
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark FBJSONSerializable Implementation

- (id)jsonSerializableRepresentation
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@implementation FBFramebuffer_FramebufferService

#pragma mark Properties

- (id<FBFramebufferImage>)createImage
{
  return [FBFramebufferImage_FrameSink imageWithFilePath:self.configuration.imagePath frameGenerator:self.frameGenerator eventSink:self.eventSink];
}

- (id<FBFramebufferVideo>)createVideo
{
  return [FBFramebufferVideo_BuiltIn videoWithConfiguration:self.configuration.encoder frameGenerator:self.frameGenerator logger:self.logger eventSink:self.eventSink];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Framebuffer %@",
    self.frameGenerator
  ];
}

#pragma mark FBJSONSerializable Implementation

- (id)jsonSerializableRepresentation
{
  return self.frameGenerator.jsonSerializableRepresentation;
}

@end

@implementation FBFramebuffer_IOSurface

#pragma mark Initializers

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration eventSink:(id<FBSimulatorEventSink>)eventSink frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator surface:(FBFramebufferSurface *)surface logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithConfiguration:configuration eventSink:eventSink frameGenerator:frameGenerator logger:logger];
  if (!self) {
    return nil;
  }

  _surface = surface;

  return self;
}

#pragma mark Public

- (BOOL)attachSurfaceConsumer:(id<FBFramebufferSurfaceConsumer>)consumer error:(NSError **)error
{
  [self.surface attachConsumer:consumer];
  return YES;
}

- (BOOL)detachSurfaceConsumer:(id<FBFramebufferSurfaceConsumer>)consumer error:(NSError **)error
{
  [self.surface detachConsumer:consumer];
  return YES;
}

#pragma mark Properties

- (id<FBFramebufferImage>)createImage
{
  return [FBFramebufferImage_Surface imageWithFilePath:self.configuration.imagePath surface:self.surface eventSink:self.eventSink];
}

- (id<FBFramebufferVideo>)createVideo
{
  return FBFramebufferVideo_SimulatorKit.isSupported
    ? [FBFramebufferVideo_SimulatorKit videoWithConfiguration:self.configuration.encoder surface:self.surface logger:self.logger eventSink:self.eventSink]
    : [FBFramebufferVideo_BuiltIn videoWithConfiguration:self.configuration.encoder frameGenerator:self.frameGenerator logger:self.logger eventSink:self.eventSink];
}

@end

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

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <SimulatorKit/SimDeviceIOPortConsumer-Protocol.h>
#import <SimulatorKit/SimDisplayVideoWriter.h>

#import <IOSurface/IOSurfaceBase.h>
#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceIO.h>
#import <CoreSimulator/SimDeviceIOClient.h>

#import "FBFramebufferFrame.h"
#import "FBFramebufferFrameGenerator.h"
#import "FBSimulatorImage.h"
#import "FBSimulatorVideo.h"
#import "FBFramebufferSurface.h"
#import "FBFramebufferConfiguration.h"
#import "FBSimulator.h"
#import "FBSimulatorDiagnostics.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBSimulatorError.h"
#import "FBVideoEncoderConfiguration.h"
#import "FBSimulatorControlFrameworkLoader.h"

@interface FBFramebuffer ()

@property (nonatomic, strong, readonly) FBFramebufferConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) FBFramebufferFrameGenerator *frameGenerator;

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator surface:(nullable FBFramebufferSurface *)surface logger:(id<FBControlCoreLogger>)logger;

@end

@implementation FBFramebuffer

@synthesize image = _image;
@synthesize video = _video;

#pragma mark Initializers

+ (void)initialize
{
  [FBSimulatorControlFrameworkLoader.xcodeFrameworks loadPrivateFrameworksOrAbort];
}

+ (dispatch_queue_t)createClientQueue
{
  return dispatch_queue_create("com.facebook.fbsimulatorcontrol.framebuffer.client", DISPATCH_QUEUE_SERIAL);
}

+ (id<FBControlCoreLogger>)loggerForSimulator:(FBSimulator *)simulator queue:(dispatch_queue_t)queue
{
  return [simulator.logger withName:[NSString stringWithFormat:@"%@:", simulator.udid]];
}

+ (instancetype)framebufferWithSurface:(FBFramebufferSurface *)surface configuration:(FBFramebufferConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  dispatch_queue_t queue = self.createClientQueue;
  id<FBControlCoreLogger> logger = [self loggerForSimulator:simulator queue:queue];

  // Otherwise we have to use the built-in frame generation.
  FBFramebufferFrameGenerator *frameGenerator = [FBFramebufferIOSurfaceFrameGenerator
    generatorWithRenderable:surface
    scale:configuration.scaleValue
    queue:queue
    logger:logger];
  return [[FBFramebuffer alloc] initWithConfiguration:configuration frameGenerator:frameGenerator surface:surface logger:logger];
}

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator surface:(nullable FBFramebufferSurface *)surface logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _frameGenerator = frameGenerator;
  _surface = surface;
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

#pragma mark Properties

- (FBSimulatorImage *)image
{
  if (!_image) {
    _image = [self createImage];
  }
  return _image;
}

- (FBSimulatorVideo *)video
{
  if (!_video) {
    _video = [self createVideo];
  }
  return _video;
}

- (FBSimulatorImage *)createImage
{
  return [FBSimulatorImage imageWithSurface:self.surface];
}

- (FBSimulatorVideo *)createVideo
{
  return [FBSimulatorVideo videoWithConfiguration:self.configuration.encoder surface:self.surface logger:self.logger];
}

#pragma mark FBJSONSerializable Implementation

- (id)jsonSerializableRepresentation
{
  return self.frameGenerator.jsonSerializableRepresentation;
}

@end

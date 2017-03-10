/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferVideo.h"

#import <objc/runtime.h>

#import <FBControlCore/FBControlCore.h>

#import "FBFramebufferFrame.h"
#import "FBFramebufferConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBVideoEncoderConfiguration.h"
#import "FBVideoEncoderBuiltIn.h"
#import "FBFramebufferFrameGenerator.h"
#import "FBVideoEncoderSimulatorKit.h"

@interface FBFramebufferVideo ()

@property (nonatomic, strong, readonly) FBVideoEncoderConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;

@property (nonatomic, strong, readwrite) id encoder;

@end

@interface FBFramebufferVideo_BuiltIn : FBFramebufferVideo

@property (nonatomic, strong, readonly) FBFramebufferFrameGenerator *frameGenerator;

- (instancetype)initWithConfiguration:(FBVideoEncoderConfiguration *)configuration frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink;

@end

@interface FBFramebufferVideo_SimulatorKit : FBFramebufferVideo

@property (nonatomic, strong, readonly) FBFramebufferSurface *surface;

- (instancetype)initWithConfiguration:(FBVideoEncoderConfiguration *)configuration surface:(FBFramebufferSurface *)surface logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink;

@end

@implementation FBFramebufferVideo

#pragma mark Initializers

+ (instancetype)videoWithConfiguration:(FBVideoEncoderConfiguration *)configuration frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
{
  return [[FBFramebufferVideo_BuiltIn alloc] initWithConfiguration:configuration frameGenerator:frameGenerator logger:logger eventSink:eventSink];
}

+ (instancetype)videoWithConfiguration:(FBVideoEncoderConfiguration *)configuration surface:(FBFramebufferSurface *)surface logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
{
  return [[FBFramebufferVideo_SimulatorKit alloc] initWithConfiguration:configuration surface:surface logger:logger eventSink:eventSink];
}

- (instancetype)initWithConfiguration:(FBVideoEncoderConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _logger = logger;
  _eventSink = eventSink;

  return self;
}

#pragma mark Public Methods

- (void)startRecordingToFile:(NSString *)filePath group:(dispatch_group_t)group;
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (void)stopRecording:(dispatch_group_t)group
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

+ (BOOL)surfaceSupported
{
  return FBVideoEncoderSimulatorKit.isSupported;
}

@end

@implementation FBFramebufferVideo_BuiltIn

#pragma mark Initializers

- (instancetype)initWithConfiguration:(FBVideoEncoderConfiguration *)configuration frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
{
  self = [super initWithConfiguration:configuration logger:logger eventSink:eventSink];
  if (!self) {
    return nil;
  }

  _frameGenerator = frameGenerator;

  return self;
}

#pragma mark Public Methods

- (void)startRecordingToFile:(NSString *)filePath group:(dispatch_group_t)group
{
  if (self.encoder) {
    [self.logger log:@"Cannot Start Recording, there is already an active encoder"];
    return;
  }
  // Choose the Path for the Log
  NSString *path = filePath ?: self.configuration.filePath;

  // Create the encoder and start it
  self.encoder = [FBVideoEncoderBuiltIn encoderWithConfiguration:self.configuration videoPath:path logger:self.logger];
  [self.encoder startRecording:group ?: dispatch_group_create()];

  // Register the encoder with the Frame Generator
  [self.frameGenerator attachSink:self.encoder];

  // Report the availability of the video
  FBDiagnostic *diagnostic = [[[[[FBDiagnosticBuilder builder]
    updatePath:path]
    updateFileType:self.configuration.fileType]
    updatePath:path]
    build];
  [self.eventSink diagnosticAvailable:diagnostic];
}

- (void)stopRecording:(dispatch_group_t)group
{
  if (!self.encoder) {
    [self.logger log:@"Cannot Stop Recording, there is no active encoder"];
    return;
  }

  // Detach the Encoder, stop, then release it.
  [self.frameGenerator detachSink:self.encoder];
  [self.encoder stopRecording:group ?: dispatch_group_create()];
  self.encoder = nil;
}

#pragma mark FBFramebufferFrameSink Implementation

- (void)frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator didUpdate:(FBFramebufferFrame *)frame
{
  [self.encoder frameGenerator:frameGenerator didUpdate:frame];
}

- (void)frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator didBecomeInvalidWithError:(NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
  [self.encoder frameGenerator:frameGenerator didBecomeInvalidWithError:error teardownGroup:teardownGroup];
}

@end

@implementation FBFramebufferVideo_SimulatorKit


- (instancetype)initWithConfiguration:(FBVideoEncoderConfiguration *)configuration surface:(FBFramebufferSurface *)surface logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
{
  self = [super initWithConfiguration:configuration logger:logger eventSink:eventSink];
  if (!self) {
    return nil;
  }

  _surface = surface;

  BOOL pendingStart = (configuration.options & FBVideoEncoderOptionsAutorecord) == FBVideoEncoderOptionsAutorecord;
  if (pendingStart) {
    [self startRecordingToFile:nil group:dispatch_group_create()];
  }

  return self;
}

#pragma mark Public

- (void)startRecordingToFile:(NSString *)filePath group:(dispatch_group_t)group;
{
  if (self.encoder) {
    [self.logger log:@"Cannot Start Recording, there is already an active encoder"];
    return;
  }
  // Choose the Path for the Log
  NSString *path = filePath ?: self.configuration.filePath;

  // Create and start the encoder.
  self.encoder = [FBVideoEncoderSimulatorKit encoderWithRenderable:self.surface videoPath:path logger:self.logger];
  [self.encoder startRecording:group ?: dispatch_group_create()];

  // Report the availability of the video
  FBDiagnostic *diagnostic = [[[[[FBDiagnosticBuilder builder]
    updatePath:path]
    updateFileType:self.configuration.fileType]
    updatePath:path]
    build];
  [self.eventSink diagnosticAvailable:diagnostic];
}

- (void)stopRecording:(dispatch_group_t)group
{
  if (!self.encoder) {
    [self.logger log:@"Cannot Stop Recording, there is no active encoder"];
    return;
  }

  // Stop and release the encoder
  [self.encoder stopRecording:group ?: dispatch_group_create()];
  self.encoder = nil;
}

@end

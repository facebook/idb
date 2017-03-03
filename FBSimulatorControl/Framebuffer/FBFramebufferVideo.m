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
#import "FBFramebufferSurfaceClient.h"
#import "FBFramebufferRenderable.h"
#import "FBVideoEncoderBuiltIn.h"
#import "FBVideoEncoderSimulatorKit.h"

@interface FBFramebufferVideo_BuiltIn ()

@property (nonatomic, strong, readonly) FBFramebufferConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;
@property (nonatomic, strong, readwrite) FBVideoEncoderBuiltIn *encoder;

@end

@implementation FBFramebufferVideo_BuiltIn

#pragma mark Initializers

+ (instancetype)withConfiguration:(FBFramebufferConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
{
  return [[self alloc] initWithConfiguration:configuration logger:logger eventSink:eventSink];
}

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
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

- (void)startRecordingToFile:(NSString *)filePath group:(dispatch_group_t)group
{
  if (self.encoder) {
    [self.logger log:@"Cannot Start Recording, there is already an active encoder"];
    return;
  }
  // Construct the Path for the Log
  FBDiagnosticBuilder *logBuilder = [FBDiagnosticBuilder builderWithDiagnostic:self.configuration.diagnostic];
  NSString *path = filePath ?: logBuilder.createPath;

  // Create the encoder and start it
  self.encoder = [FBVideoEncoderBuiltIn encoderWithConfiguration:self.configuration videoPath:path logger:self.logger];
  [self.encoder startRecording:group ?: dispatch_group_create()];

  // Report the availability of the video
  [self.eventSink diagnosticAvailable:[[logBuilder updatePath:path] build]];
}

- (void)stopRecording:(dispatch_group_t)group
{
  if (!self.encoder) {
    [self.logger log:@"Cannot Stop Recording, there is no active encoder"];
    return;
  }

  // Stop the encoder, and release it.
  [self.encoder stopRecording:group ?: dispatch_group_create()];
  self.encoder = nil;
}

#pragma mark FBFramebufferFrameSink Implementation

- (void)framebuffer:(FBFramebuffer *)framebuffer didUpdate:(FBFramebufferFrame *)frame
{
  [self.encoder framebuffer:framebuffer didUpdate:frame];
}

- (void)framebuffer:(FBFramebuffer *)framebuffer didBecomeInvalidWithError:(NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
  [self.encoder framebuffer:framebuffer didBecomeInvalidWithError:error teardownGroup:teardownGroup];
}

@end

@interface FBFramebufferVideo_SimulatorKit ()

@property (nonatomic, strong, readonly) FBFramebufferConfiguration *configuration;
@property (nonatomic, strong, readonly) FBFramebufferRenderable *renderable;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;

@property (nonatomic, strong, readwrite) FBVideoEncoderSimulatorKit *encoder;

@end

@implementation FBFramebufferVideo_SimulatorKit

+ (instancetype)withConfiguration:(FBFramebufferConfiguration *)configuration renderable:(FBFramebufferRenderable *)renderable logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
{
  return [[self alloc] initWithConfiguration:configuration renderable:renderable logger:logger eventSink:eventSink];
}

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration renderable:(FBFramebufferRenderable *)renderable logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _renderable = renderable;
  _logger = logger;
  _eventSink = eventSink;

  BOOL pendingStart = (configuration.videoOptions & FBFramebufferVideoOptionsAutorecord) == FBFramebufferVideoOptionsAutorecord;
  if (pendingStart) {
    [self startRecordingToFile:nil group:dispatch_group_create()];
  }

  return self;
}

#pragma mark Public

+ (BOOL)isSupported
{
  return FBVideoEncoderSimulatorKit.isSupported;
}

- (void)startRecordingToFile:(NSString *)filePath group:(dispatch_group_t)group;
{
  if (self.encoder) {
    [self.logger log:@"Cannot Start Recording, there is already an active encoder"];
    return;
  }

  // Construct the Path for the Log
  FBDiagnosticBuilder *logBuilder = [FBDiagnosticBuilder builderWithDiagnostic:self.configuration.diagnostic];
  NSString *path = filePath ?: logBuilder.createPath;

  // Create and start the encoder.
  self.encoder = [FBVideoEncoderSimulatorKit encoderWithRenderable:self.renderable videoPath:path logger:self.logger];
  [self.encoder startRecording:group ?: dispatch_group_create()];

  // Report the availability of the video
  [self.eventSink diagnosticAvailable:[[logBuilder updatePath:path] build]];
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

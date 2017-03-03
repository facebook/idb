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

#import <SimulatorKit/SimDisplayVideoWriter.h>
#import <SimulatorKit/SimDisplayVideoWriter+Removed.h>

#import "FBFramebufferFrame.h"
#import "FBFramebufferConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBFramebufferSurfaceClient.h"
#import "FBFramebufferRenderable.h"
#import "FBVideoEncoderBuiltIn.h"

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

- (void)startRecording:(dispatch_group_t)group
{
  if (self.encoder) {
    [self.logger log:@"Cannot Start Recording, there is already an active encoder"];
    return;
  }
  // Construct the Path for the Log
  FBDiagnosticBuilder *logBuilder = [FBDiagnosticBuilder builderWithDiagnostic:self.configuration.diagnostic];
  NSString *path = logBuilder.createPath;

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
@property (nonatomic, strong, readonly) dispatch_queue_t mediaQueue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;

@property (nonatomic, strong, readonly) SimDisplayVideoWriter *writer;
@property (nonatomic, strong, readonly) FBDiagnostic *diagnostic;

@end

@implementation FBFramebufferVideo_SimulatorKit

+ (instancetype)withConfiguration:(FBFramebufferConfiguration *)configuration ioClient:(SimDeviceIOClient *)ioClient logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbsimulatorcontrol.video.simulatorkit", DISPATCH_QUEUE_SERIAL);
  FBFramebufferRenderable *renderable = [FBFramebufferRenderable mainScreenRenderableForClient:ioClient];
  logger = [logger onQueue:queue];
  return [[self alloc] initWithConfiguration:configuration renderable:renderable onQueue:queue logger:logger eventSink:eventSink];
}

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration renderable:(FBFramebufferRenderable *)renderable onQueue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _renderable = renderable;
  _logger = logger;
  _eventSink = eventSink;
  _mediaQueue = queue;

  FBDiagnosticBuilder *logBuilder = [FBDiagnosticBuilder builderWithDiagnostic:self.configuration.diagnostic];
  NSString *path = logBuilder.createPath;
  NSURL *url = [NSURL fileURLWithPath:path];
  _diagnostic = [[logBuilder updatePath:path] build];
  _writer = [self createVideoWriterForURL:url mediaQueue:queue];

  BOOL pendingStart = (configuration.videoOptions & FBFramebufferVideoOptionsAutorecord) == FBFramebufferVideoOptionsAutorecord;
  if (pendingStart) {
    [self startRecording:dispatch_group_create()];
  }

  return self;
}

- (SimDisplayVideoWriter *)createVideoWriterForURL:(NSURL *)url mediaQueue:(dispatch_queue_t)mediaQueue
{
  Class class = objc_getClass("SimDisplayVideoWriter");
  if ([class respondsToSelector:@selector(videoWriterForURL:fileType:)]) {
    return [class videoWriterForURL:url fileType:@"mp4"];
  }
  return [class videoWriterForURL:url fileType:@"mp4" completionQueue:mediaQueue completionHandler:^{
    // This should be used as a semaphore for the stopRecording: dispatch_group.
    // As it stands, the behaviour is currently the same as before.
  }];
}

+ (BOOL)isSupported
{
  return objc_getClass("SimDisplayVideoWriter") != nil;
}

- (void)startRecording:(dispatch_group_t)group
{
  dispatch_group_async(group, self.mediaQueue, ^{
    [self startRecordingNowWithError:nil];
  });
}

- (void)stopRecording:(dispatch_group_t)group
{
  dispatch_group_async(group, self.mediaQueue, ^{
    [self stopRecordingNowWithError:nil];
  });
}

#pragma mark Private

- (BOOL)startRecordingNowWithError:(NSError **)error
{
  // Don't hit an assertion because we write twice.
  if (self.writer.startedWriting) {
    return YES;
  }
  // Start for real. -[SimDisplayVideoWriter startWriting]
  // must be called before sending a surface and damage rect.
  [self.logger log:@"Start Writing in Video Writer"];
  [self.writer startWriting];
  [self.logger log:@"Attaching Consumer in Video Writer"];
  [self.renderable attachConsumer:self.writer];

  // Notify the event sink.
  [self.eventSink diagnosticAvailable:self.diagnostic];

  return YES;
}

- (BOOL)stopRecordingNowWithError:(NSError **)error
{
  // Don't hit an assertion because we're not started.
  if (!self.writer.startedWriting) {
    return YES;
  }

  // Detach the Consumer first, we don't want to send any more Damage Rects.
  // If a Damage Rect send races with finishWriting, a crash can occur.
  [self.logger log:@"Detaching Consumer in Video Writer"];
  [self.renderable detachConsumer:self.writer];
  // Now there are no more incoming rects, tear down the video encoding.
  [self.logger log:@"Finishing Writing in Video Writer"];
  [self.writer finishWriting];

  return YES;
}

@end

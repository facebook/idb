/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBVideoEncoderSimulatorKit.h"

#import <FBControlCore/FBControlCore.h>

#import <objc/runtime.h>
#import <xpc/xpc.h>
#import <IOSurface/IOSurface.h>

#import <SimulatorKit/SimDisplayVideoWriter.h>
#import <SimulatorKit/SimDisplayVideoWriter+Removed.h>

#import "FBFramebufferRenderable.h"

@interface FBVideoEncoderSimulatorKit () <FBFramebufferRenderableConsumer>

@property (nonatomic, strong, readonly) FBFramebufferRenderable *renderable;
@property (nonatomic, strong, readonly) dispatch_queue_t mediaQueue;
@property (nonatomic, strong, readonly) SimDisplayVideoWriter *writer;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBVideoEncoderSimulatorKit

+ (instancetype)encoderWithRenderable:(FBFramebufferRenderable *)renderable videoPath:(NSString *)videoPath logger:(nullable id<FBControlCoreLogger>)logger
{
  NSURL *fileURL = [NSURL fileURLWithPath:videoPath];
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbsimulatorcontrol.videoencoder.simulatorkit", DISPATCH_QUEUE_SERIAL);
  logger = [logger onQueue:queue];
  return [[self alloc] initWithRenderable:renderable fileURL:fileURL mediaQueue:queue logger:logger];
}

- (instancetype)initWithRenderable:(FBFramebufferRenderable *)renderable fileURL:(NSURL *)fileURL mediaQueue:(dispatch_queue_t)mediaQueue logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _renderable = renderable;
  _logger = logger;
  _mediaQueue = mediaQueue;
  _writer = [self createVideoWriterForURL:fileURL mediaQueue:mediaQueue];

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

#pragma mark Public

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
  [self.renderable attachConsumer:self];

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
  [self.renderable detachConsumer:self];
  // Now there are no more incoming rects, tear down the video encoding.
  [self.logger log:@"Finishing Writing in Video Writer"];
  [self.writer finishWriting];

  return YES;
}

#pragma mark FBFramebufferConsumable

- (void)didChangeIOSurface:(IOSurfaceRef)surface
{
  if (!surface) {
    [self.writer didChangeIOSurface:NULL];
    return;
  }
  xpc_object_t xpcSurface = IOSurfaceCreateXPCObject(surface);
  [self.writer didChangeIOSurface:xpcSurface];
}

- (void)didReceiveDamageRect:(CGRect)rect
{
  [self.writer didReceiveDamageRect:rect];
}

- (NSString *)consumerIdentifier
{
  return self.writer.consumerIdentifier;
}

@end

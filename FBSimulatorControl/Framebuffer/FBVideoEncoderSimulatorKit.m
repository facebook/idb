/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBVideoEncoderSimulatorKit.h"

#import <FBControlCore/FBControlCore.h>

#import <objc/runtime.h>
#import <xpc/xpc.h>
#import <IOSurface/IOSurface.h>

#import <SimulatorKit/SimDisplayVideoWriter.h>
#import <SimulatorKit/SimDisplayVideoWriter+Removed.h>

#import "FBFramebuffer.h"
#import "FBSimulatorError.h"

// A Global Block for the Video Writer completion callback.
// We place this as the -[SimDisplayVideoWriter completionHandler] as the memory management of global blocks
// means that a pointer to this block will be valid for the lifetime of the process.
// Any block that exists on the stack or heap can be a dangling pointer from -[SimVideoMP4File completionHandler]
// If we ensure that this is always a valid block (by being a global) this won't segfault when called.
// We can instead use the dispatch_io callbacks to signify termination.
void (^VideoWriterGlobalCallback)(NSError *) = ^(NSError *error){
  (void) error;
};

@interface FBVideoEncoderSimulatorKit () <FBFramebufferConsumer>

@property (nonatomic, strong, nullable, readonly) SimDisplayVideoWriter *writer;
@property (nonatomic, strong, readonly) FBFramebuffer *framebuffer;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) FBFuture<NSNull *> *finishedWriting;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *startedWriting;

@end

@implementation FBVideoEncoderSimulatorKit

#pragma mark Initializers

+ (instancetype)encoderWithFramebuffer:(FBFramebuffer *)framebuffer videoPath:(NSString *)videoPath logger:(nullable id<FBControlCoreLogger>)logger
{
  NSURL *fileURL = [NSURL fileURLWithPath:videoPath];
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbsimulatorcontrol.videoencoder.simulatorkit", DISPATCH_QUEUE_SERIAL);

  FBMutableFuture<NSNull *> *finishedWriting = [FBMutableFuture future];
  FBMutableFuture<NSNull *> *startedWriting = [FBMutableFuture future];
  SimDisplayVideoWriter *writer = [FBVideoEncoderSimulatorKit createVideoWriterForURL:fileURL mediaQueue:queue startedWriting:startedWriting finishedWriting:finishedWriting logger:logger];

  return [[self alloc] initWithWriter:writer framebuffer:framebuffer fileURL:fileURL mediaQueue:queue startedWriting:startedWriting finishedWriting:finishedWriting logger:logger];
}

+ (SimDisplayVideoWriter *)createVideoWriterForURL:(NSURL *)url mediaQueue:(dispatch_queue_t)mediaQueue startedWriting:(FBMutableFuture<NSNull *> *)startedWriting finishedWriting:(FBMutableFuture<NSNull *> *)finishedWriting logger:(nullable id<FBControlCoreLogger>)logger
{
  Class class = objc_getClass("SimDisplayVideoWriter");

  // When the VideoWriter API doesn't have a callback mechanism, assume that the finishedWriting call is synchronous.
  // This means that the future that is returned from the public API will return the pre-finished future.
  if ([class respondsToSelector:@selector(videoWriterForURL:fileType:)]) {
    [finishedWriting resolveWithResult:NSNull.null];
    return [class videoWriterForURL:url fileType:@"mp4"];
  }

  // Create the dispatch_io as a stream for the Video Writer.
  dispatch_io_t io = dispatch_io_create_with_path(
    DISPATCH_IO_STREAM,
    url.fileSystemRepresentation,
    (O_WRONLY |O_CREAT | O_TRUNC),
    (S_IWUSR | S_IRUSR | S_IRGRP | S_IROTH),
    mediaQueue,
    ^(int errorCode) {
      if (errorCode == 0) {
        [logger logFormat:@"Finished writing video at path %@", url];
        [finishedWriting resolveWithResult:NSNull.null];
      } else {
        NSError *error = [[FBSimulatorError
          describeFormat:@"IO Stream for %@ exited with errorcode %d", url, errorCode]
          build];
        [finishedWriting resolveWithError:error];
      }
    }
  );
  // Fail early if the IO channel wasn't created.
  if (!io) {
    NSError *error = [[FBSimulatorError describeFormat:@"Failed to create IO channel for %@", url] build];
    [startedWriting resolveWithError:error];
    [finishedWriting resolveWithError:error];
    return nil;
  }

  // Pass the global callback and a global queue so that we never get a dangling-pointer called in the callback.
  // These object-references will be valid for the lifetime of the process.
  return [class
    videoWriterForDispatchIO:io
    fileType:@"mp4"
    completionQueue:dispatch_get_main_queue()
    completionHandler:VideoWriterGlobalCallback];
}

- (instancetype)initWithWriter:(nullable SimDisplayVideoWriter *)writer framebuffer:(FBFramebuffer *)framebuffer fileURL:(NSURL *)fileURL mediaQueue:(dispatch_queue_t)mediaQueue startedWriting:(FBMutableFuture<NSNull *> *)startedWriting finishedWriting:(FBFuture<NSNull *> *)finishedWriting logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _writer = writer;
  _framebuffer = framebuffer;
  _mediaQueue = mediaQueue;
  _finishedWriting = finishedWriting;
  _startedWriting = startedWriting;
  _logger = logger;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"SimulatorKit Encoder %@", self.writer];
}

#pragma mark Public

+ (BOOL)isSupported
{
  return objc_getClass("SimDisplayVideoWriter") != nil;
}

- (FBFuture<NSNull *> *)startRecording
{
  return [FBFuture onQueue:self.mediaQueue resolve:^{
    return [self startRecordingNow];
  }];
}

- (FBFuture<NSNull *> *)stopRecording
{
  return [FBFuture onQueue:self.mediaQueue resolve:^{
    return [self stopRecordingNow];
  }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)startRecordingNow
{
  // Fail-fast if we're already in an error state.
  if (self.startedWriting.error) {
    return self.startedWriting;
  }
  // Don't start twice.
  if (self.startedWriting.hasCompleted) {
    return [[FBSimulatorError
      describeFormat:@"Cannot start recording, we requested to start writing once."]
      failFuture];
  }
  // Don't hit an assertion because we write twice.
  if (self.writer.startedWriting) {
    return [[FBSimulatorError
      describeFormat:@"Cannot start recording, the writer has started writing."]
      failFuture];
  }

  // Start for real. -[SimDisplayVideoWriter startWriting]
  // must be called before sending a surface and damage rect.
  [self.logger log:@"Start Writing in Video Writer"];
  [self.writer startWriting];
  [self.logger log:@"Attaching Consumer in Video Writer"];
  IOSurfaceRef surface = [self.framebuffer attachConsumer:self onQueue:self.mediaQueue];
  if (surface) {
    dispatch_async(self.mediaQueue, ^{
      [self didChangeIOSurface:surface];
    });
  }

  // Return the future that we've wrapped.
  return self.startedWriting;
}

- (FBFuture<NSNull *> *)stopRecordingNow
{
  // Fail-fast if we're already in an error state.
  if (self.finishedWriting.error) {
    return self.finishedWriting;
  }
  // If we've resolved already, we've called stop twice.
  if (self.finishedWriting.hasCompleted) {
    return [[FBSimulatorError
      describeFormat:@"Cannot stop recording, we've requested to stop recording once."]
      failFuture];
  }
  // Don't hit an assertion because we're not started.
  if (!self.writer.startedWriting) {
    return [[FBSimulatorError
      describeFormat:@"Cannot stop recording, the writer has not started writing."]
      failFuture];
  }

  // Detach the Consumer first, we don't want to send any more Damage Rects.
  // If a Damage Rect send races with finishWriting, a crash can occur.
  [self.logger log:@"Detaching Consumer in Video Writer"];
  [self.framebuffer detachConsumer:self];
  // Now there are no more incoming rects, tear down the video encoding.
  [self.logger log:@"Finishing Writing in Video Writer"];
  [self.writer finishWriting];

  // Return the future that we've wrapped.
  return self.finishedWriting;
}

#pragma mark FBFramebufferConsumable

- (void)didChangeIOSurface:(IOSurfaceRef)surface
{
  if (!surface) {
    [self.logger log:@"IOSurface Removed"];
    [self.writer didChangeIOSurface:NULL];
    return;
  }
  [self.logger logFormat:@"IOSurface for Encoder %@ changed to %@", self, surface];
  [self.startedWriting resolveWithResult:NSNull.null];
  if (FBXcodeConfiguration.isXcode9OrGreater) {
    [self.writer didChangeIOSurface:(__bridge id) surface];
  } else {
    xpc_object_t xpcSurface = IOSurfaceCreateXPCObject(surface);
    [self.writer didChangeIOSurface:xpcSurface];
  }
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

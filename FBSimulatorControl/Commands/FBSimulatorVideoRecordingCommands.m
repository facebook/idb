/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorVideoRecordingCommands.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBFramebuffer.h"
#import "FBSimulatorVideo.h"
#import "FBFramebufferSurface.h"
#import "FBSimulatorBitmapStream.h"

@interface FBSimulatorVideoRecordingCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorVideoRecordingCommands

+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  return [[self alloc] initWithSimulator:target];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  return self;
}

#pragma mark FBVideoRecordingCommands Implementation

- (FBFuture<id<FBVideoRecordingSession>> *)startRecordingToFile:(NSString *)filePath
{
  NSError *error = nil;
  FBSimulatorVideo *video = [self obtainSimulatorVideoWithError:&error];
  if (!video) {
    return [FBSimulatorError failFutureWithError:error];
  }
  return [[video
    startRecordingToFile:filePath]
    mapReplace:video];
}

- (FBFuture<NSNull *> *)stopRecording
{
  NSError *error = nil;
  FBSimulatorVideo *video = [self obtainSimulatorVideoWithError:&error];
  if (!video) {
    return [FBSimulatorError failFutureWithError:error];
  }
  return [video stopRecording];
}

#pragma mark FBSimulatorStreamingCommands

- (FBFuture<FBSimulatorBitmapStream *> *)createStreamWithConfiguration:(FBBitmapStreamConfiguration *)configuration
{
  if (![configuration.encoding isEqualToString:FBBitmapStreamEncodingBGRA]) {
    return [[FBSimulatorError
      describe:@"Only BGRA is supported for simulators."]
      failFuture];
  }

  NSError *error = nil;
  FBFramebufferSurface *surface = [self obtainSurfaceWithError:&error];
  if (!surface) {
    return [FBFuture futureWithError:error];
  }
  id<FBControlCoreLogger> logger = self.simulator.logger;
  NSNumber *framesPerSecond = configuration.framesPerSecond;
  if (framesPerSecond) {
    return [FBFuture futureWithResult:[FBSimulatorBitmapStream eagerStreamWithSurface:surface framesPerSecond:framesPerSecond.unsignedIntegerValue logger:logger]];
  }
  return [FBFuture futureWithResult:[FBSimulatorBitmapStream lazyStreamWithSurface:surface logger:logger]];
}

#pragma mark Private

- (FBSimulatorVideo *)obtainSimulatorVideoWithError:(NSError **)error
{
  NSError *innerError = nil;
  FBFramebuffer *framebuffer = [self.simulator framebufferWithError:&innerError];
  if (!framebuffer) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  FBSimulatorVideo *video = framebuffer.video;
  if (!video) {
    return [[[FBSimulatorError
      describe:@"Simulator Does not have a FBSimulatorVideo instance"]
      inSimulator:self.simulator]
      fail:error];
  }
  return video;
}

- (FBFramebufferSurface *)obtainSurfaceWithError:(NSError **)error
{
  NSError *innerError = nil;
  FBFramebuffer *framebuffer = [self.simulator framebufferWithError:&innerError];
  if (!framebuffer) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  FBFramebufferSurface *surface = framebuffer.surface;
  if (!surface) {
    return [[FBSimulatorError
      describe:@"Framebuffer does not have a surface"]
      fail:error];
  }
  return surface;
}

@end

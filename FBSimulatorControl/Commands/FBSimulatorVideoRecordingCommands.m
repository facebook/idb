/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorVideoRecordingCommands.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorSet.h"
#import "FBFramebuffer.h"
#import "FBSimulatorVideo.h"
#import "FBSimulatorBitmapStream.h"
#import "FBVideoEncoderConfiguration.h"

@interface FBSimulatorVideoRecordingCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;
@property (nonatomic, strong, nullable, readwrite) FBSimulatorVideo *video;

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

- (FBFuture<id<FBiOSTargetContinuation>> *)startRecordingToFile:(NSString *)filePath
{
  return [[self
    obtainVideo]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorVideo *video) {
      return [[video startRecordingToFile:filePath] mapReplace:video];
    }];
}

- (FBFuture<NSNull *> *)stopRecording
{
  return [[FBFuture
    onQueue:self.simulator.workQueue resolve:^ FBFuture<NSNull *> * {
       if (!self.video) {
         return [[FBSimulatorError
          describe:@"Cannot start recording, there is not an active recorder"]
          failFuture];
       }
       return [self.video stopRecording];
    }]
    onQueue:self.simulator.workQueue notifyOfCompletion:^(id _){
      self.video = nil;
    }];
}

#pragma mark FBSimulatorStreamingCommands

- (FBFuture<FBSimulatorBitmapStream *> *)createStreamWithConfiguration:(FBBitmapStreamConfiguration *)configuration
{
  id<FBControlCoreLogger> logger = self.simulator.logger;
  return [[self.simulator
    connectToFramebuffer]
    onQueue:self.simulator.workQueue fmap:^(FBFramebuffer *framebuffer) {
      return [FBSimulatorVideoRecordingCommands streamWithFramebuffer:framebuffer encoding:configuration.encoding framesPerSecond:configuration.framesPerSecond logger:logger];
    }];
}

+ (FBFuture<FBSimulatorBitmapStream *> *)streamWithFramebuffer:(FBFramebuffer *)framebuffer encoding:(FBBitmapStreamEncoding)encoding framesPerSecond:(NSNumber *)framesPerSecond logger:(id<FBControlCoreLogger>)logger
{
  return [FBFuture resolveValue:^ FBSimulatorBitmapStream * (NSError **error){
    if (framesPerSecond) {
      return [FBSimulatorBitmapStream eagerStreamWithFramebuffer:framebuffer encoding:encoding framesPerSecond:framesPerSecond.unsignedIntegerValue logger:logger error:error];
    }
    return [FBSimulatorBitmapStream lazyStreamWithFramebuffer:framebuffer encoding:encoding logger:logger error:error];
  }];
}

#pragma mark Private

- (FBFuture<FBSimulatorVideo *> *)obtainVideo
{
  if (self.video) {
    return [FBFuture futureWithResult:self.video];
  }
  if (FBSimulatorVideoRecordingCommands.shouldUseSimctlEncoder) {
    self.video = [FBSimulatorVideo videoWithSimctlExecutor:self.simulator.simctlExecutor logger:self.simulator.logger];
    return [FBFuture futureWithResult:self.video];
  }


  return [[self.simulator
    connectToFramebuffer]
    onQueue:self.simulator.workQueue map:^(FBFramebuffer *framebuffer) {
      self.video = [FBSimulatorVideo videoWithConfiguration:FBVideoEncoderConfiguration.defaultConfiguration framebuffer:framebuffer logger:self.simulator.logger];
      return self.video;
    }];
}

+ (BOOL)shouldUseSimctlEncoder
{
  return !NSProcessInfo.processInfo.environment[@"FBSIMULATORCONTROL_IN_PROCESS_RECORDER"].boolValue;
}

@end

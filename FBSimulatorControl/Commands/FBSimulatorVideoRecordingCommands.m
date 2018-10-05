/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
@property (nonatomic, strong, nullable, readwrite) FBSimulatorVideo *recorder;

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
  return [[FBFuture
    onQueue:self.simulator.workQueue resolve:^ FBFuture<FBSimulatorVideo *> * {
      if (self.recorder) {
        return [[FBSimulatorError
          describeFormat:@"Cannot start recording, there is already a recorder %@", self.recorder]
          failFuture];
      }
      return [self obtainVideoRecorder];
    }]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorVideo *recorder) {
      self.recorder = recorder;
      return [[recorder startRecordingToFile:filePath] mapReplace:recorder];
    }];
}

- (FBFuture<NSNull *> *)stopRecording
{
  return [[FBFuture
    onQueue:self.simulator.workQueue resolve:^ FBFuture<NSNull *> * {
       if (!self.recorder) {
         return [[FBSimulatorError
          describeFormat:@"Cannot start recording, there is not an active recorder %@", self.recorder]
          failFuture];
       }
       return [self.recorder stopRecording];
    }]
    onQueue:self.simulator.workQueue notifyOfCompletion:^(id _){
      self.recorder = nil;
    }];
}

#pragma mark FBSimulatorStreamingCommands

- (FBFuture<FBSimulatorBitmapStream *> *)createStreamWithConfiguration:(FBBitmapStreamConfiguration *)configuration
{
  if (![configuration.encoding isEqualToString:FBBitmapStreamEncodingBGRA]) {
    return [[FBSimulatorError
      describe:@"Only BGRA is supported for simulators."]
      failFuture];
  }
  id<FBControlCoreLogger> logger = self.simulator.logger;
  return [[self.simulator
    connectToFramebuffer]
    onQueue:self.simulator.workQueue map:^(FBFramebuffer *framebuffer) {
      NSNumber *framesPerSecond = configuration.framesPerSecond;
      if (framesPerSecond) {
        return [FBSimulatorBitmapStream eagerStreamWithFramebuffer:framebuffer framesPerSecond:framesPerSecond.unsignedIntegerValue logger:logger];
      }
      return [FBSimulatorBitmapStream lazyStreamWithFramebuffer:framebuffer logger:logger];
    }];
}

#pragma mark Private

- (FBFuture<FBSimulatorVideo *> *)obtainVideoRecorder
{
  if (FBSimulatorVideoRecordingCommands.shouldUseSimctlEncoder) {
    FBSimulatorVideo *recorder = [FBSimulatorVideo
      simctlVideoForDeviceSetPath:self.simulator.set.deviceSet.setPath
      deviceUUID:self.simulator.device.UDID.UUIDString
      logger:self.simulator.logger];
    return [FBFuture futureWithResult:recorder];
  }

  return [[self.simulator
    connectToFramebuffer]
    onQueue:self.simulator.workQueue map:^(FBFramebuffer *framebuffer) {
      FBSimulatorVideo *video = [FBSimulatorVideo videoWithConfiguration:FBVideoEncoderConfiguration.defaultConfiguration framebuffer:framebuffer logger:self.simulator.logger];
      return video;
    }];
}

+ (BOOL)shouldUseSimctlEncoder
{
  return !NSProcessInfo.processInfo.environment[@"FBSIMULATORCONTROL_IN_PROCESS_RECORDER"].boolValue;
}

@end

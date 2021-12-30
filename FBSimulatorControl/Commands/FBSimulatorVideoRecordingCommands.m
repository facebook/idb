/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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
#import "FBSimulatorVideoStream.h"

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

- (FBFuture<id<FBiOSTargetOperation>> *)startRecordingToFile:(NSString *)filePath
{
  if (self.video) {
    return [[FBSimulatorError
      describe:@"Cannot create a new video recording session, one is already active"]
      failFuture];
  }

  return [[FBSimulatorVideoRecordingCommands
    videoImplementationForSimulator:self.simulator filePath:filePath]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorVideo *video) {
      return [[video
        startRecording]
        onQueue:self.simulator.workQueue map:^(id _) {
          self.video = video;
          return video;
        }];
    }];
}

- (FBFuture<NSNull *> *)stopRecording
{
  FBSimulatorVideo *video = self.video;
  self.video = nil;
  if (!video) {
    return [[FBSimulatorError
      describeFormat:@"There was no existing video instance for %@", self.simulator]
      failFuture];
  }

  return [video stopRecording];
}

#pragma mark FBSimulatorStreamingCommands

- (FBFuture<FBSimulatorVideoStream *> *)createStreamWithConfiguration:(FBVideoStreamConfiguration *)configuration
{
  id<FBControlCoreLogger> logger = self.simulator.logger;
  return [[self.simulator
    connectToFramebuffer]
    onQueue:self.simulator.workQueue map:^ FBSimulatorVideoStream * (FBFramebuffer *framebuffer) {
      return [FBSimulatorVideoStream streamWithFramebuffer:framebuffer configuration:configuration logger:logger];
    }];
}

#pragma mark Private

+ (FBFuture<FBSimulatorVideo *> *)videoImplementationForSimulator:(FBSimulator *)simulator filePath:(NSString *)filePath
{
  FBSimulatorVideo *video = [FBSimulatorVideo videoWithSimctlExecutor:simulator.simctlExecutor filePath:filePath logger:simulator.logger];
  return [FBFuture futureWithResult:video];
}

@end

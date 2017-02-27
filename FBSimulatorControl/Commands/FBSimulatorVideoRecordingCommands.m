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
#import "FBSimulator+Connection.h"
#import "FBSimulator+Framebuffer.h"
#import "FBFramebuffer.h"
#import "FBFramebufferVideo.h"

@interface FBSimulatorVideoRecordingCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorVideoRecordingCommands

+ (instancetype)withSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
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

- (BOOL)startRecordingWithError:(NSError **)error
{
  NSError *innerError = nil;
  id<FBFramebufferVideo> video = [self obtainSimulatorVideoWithError:&innerError];
  if (!video) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  dispatch_group_t waitGroup = dispatch_group_create();
  [video startRecording:waitGroup];
  long fail = dispatch_group_wait(waitGroup, FBControlCoreGlobalConfiguration.regularDispatchTimeout);
  if (fail) {
    return [[FBSimulatorError
      describeFormat:@"Timeout waiting for video to start recording in %f seconds", FBControlCoreGlobalConfiguration.regularTimeout]
      failBool:error];
  }
  return YES;
}

- (BOOL)stopRecordingWithError:(NSError **)error
{
  NSError *innerError = nil;
  id<FBFramebufferVideo> video = [self obtainSimulatorVideoWithError:&innerError];
  if (!video) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  dispatch_group_t waitGroup = dispatch_group_create();
  [video stopRecording:waitGroup];
  long fail = dispatch_group_wait(waitGroup, FBControlCoreGlobalConfiguration.regularDispatchTimeout);
  if (fail) {
    return [[FBSimulatorError
      describeFormat:@"Timeout waiting for video to stop recording in %f seconds", FBControlCoreGlobalConfiguration.regularTimeout]
      failBool:error];
  }
  return YES;
}

#pragma mark

- (id<FBFramebufferVideo>)obtainSimulatorVideoWithError:(NSError **)error
{
  FBSimulator *simulator = self.simulator;
  if (simulator.state != FBSimulatorStateBooted) {
    return [[FBSimulatorError
      describeFormat:@"Cannot get the Video for a non-booted simulator %@", simulator]
      fail:error];
  }

  NSError *innerError = nil;
  FBFramebuffer *framebuffer = [simulator framebufferWithError:&innerError];
  if (!framebuffer) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  id<FBFramebufferVideo> video = framebuffer.video;
  if (!video) {
    return [[[FBSimulatorError
      describe:@"Simulator Does not have a FBFramebufferVideo instance"]
      inSimulator:simulator]
      fail:error];
  }
  return video;
}

@end

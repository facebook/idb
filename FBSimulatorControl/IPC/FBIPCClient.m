/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBIPCClient.h"

#import "FBSimulator.h"
#import "FBSimulatorSet.h"
#import "FBSimulatorFramebuffer.h"
#import "FBSimulatorBridge.h"
#import "FBFramebufferVideo.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBIPCManager.h"

@interface FBIPCClient ()


@property (nonatomic, strong, readonly) NSDistributedNotificationCenter *notificationCenter;

@end

@implementation FBIPCClient

+ (instancetype)withSimulatorSet:(FBSimulatorSet *)set
{
  return [[self alloc] initWithSet:set];
}

- (instancetype)initWithSet:(FBSimulatorSet *)set
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;

  return self;
}

#pragma mark Public Methods

- (void)startRecordingVideo:(FBSimulator *)simulator
{
  if (simulator.set != self.set) {
    return;
  }
  if (simulator.bridge) {
    [simulator.bridge.framebuffer.video startRecording];
  }
  // TODO: IPC CALL
}

- (void)stopRecordingVideo:(FBSimulator *)simulator
{
  if (simulator.set != self.set) {
    return;
  }
  if (simulator.bridge) {
    [simulator.bridge.framebuffer.video stopRecording];
  }
  // TODO: IPC CALL
}


@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorBridgeCommands.h"

#import <FBControlCore/FBControlCore.h>

#import "FBFramebuffer.h"
#import "FBSimulator.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorError.h"
#import "FBSimulatorVideoRecordingCommands.h"

@interface FBSimulatorBridgeCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorBridgeCommands

#pragma mark Initializers

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

#pragma mark FBSimulatorBridgeCommands

- (FBFuture<NSNull *> *)setLocationWithLatitude:(double)latitude longitude:(double)longitude
{
  return [[self.simulator
    connectToBridge]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorBridge *bridge) {
      return [bridge setLocationWithLatitude:latitude longitude:longitude];
    }];
}

- (FBFuture<NSNull *> *)setHardwareKeyboardEnabled:(BOOL)isEnabled keyboardType:(unsigned char)keyboardType
{
  return [[self.simulator
           connectToBridge]
          onQueue:self.simulator.workQueue fmap:^(FBSimulatorBridge *bridge) {
            return [bridge setHardwareKeyboardEnabled:isEnabled keyboardType:keyboardType];
          }];
}

@end

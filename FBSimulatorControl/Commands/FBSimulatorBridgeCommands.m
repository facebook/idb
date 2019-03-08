/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

@end

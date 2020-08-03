/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorLocationCommands.h"

#import "FBSimulator.h"
#import "FBSimulatorBridge.h"

@interface FBSimulatorLocationCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorLocationCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBSimulator *)targets
{
  return [[self alloc] initWithSimulator:targets];
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

#pragma mark FBSimulatorLocationCommands Protocol Implementation

- (FBFuture<NSNull *> *)overrideLocationWithLongitude:(double)longitude latitude:(double)latitude
{
  return [[self.simulator
    connectToBridge]
    onQueue:self.simulator.workQueue fmap:^ FBFuture<NSNull *> * (FBSimulatorBridge *bridge) {
      return [bridge setLocationWithLatitude:latitude longitude:longitude];
    }];
}

@end

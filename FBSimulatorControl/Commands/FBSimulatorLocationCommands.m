/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDevice.h>
#import "FBSimulatorLocationCommands.h"

#import "FBSimulator.h"

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
  return [FBFuture onQueue:self.simulator.workQueue resolveValue:^NSNull *(NSError **error) {
    if (![self.simulator.device setLocationWithLatitude:latitude andLongitude:longitude error:error]) {
      return nil;
    }
    return NSNull.null;
  }];
}

@end

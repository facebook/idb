/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDevice.h>
#import "FBSimulatorMemoryCommands.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import <FBControlCore/FBiOSTarget.h>

@interface FBSimulatorMemoryCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorMemoryCommands

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

#pragma mark FBMemoryCommands Protocol Implementation

- (FBFuture<NSNull *> *)simulateMemoryWarning
{
  if ([self.simulator.device respondsToSelector:(@selector(simulateMemoryWarning))]) {
    return [FBFuture onQueue:self.simulator.workQueue resolve:^ FBFuture<NSNull *> * () {
      [self.simulator.device simulateMemoryWarning];

      return FBFuture.empty;
    }];
  }

  return [[FBSimulatorError
            describe:@"SimDevice doesn't have simulateMemoryWarning selector"]
            failFuture];
}

@end

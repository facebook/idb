/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorProcessSpawnCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBAgentLaunchStrategy.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBSimulatorProcessSpawnCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorProcessSpawnCommands

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

#pragma mark FBSimulatorProcessSpawnCommands Implementation

- (FBFuture<id<FBLaunchedProcess>> *)launchProcess:(FBProcessSpawnConfiguration *)configuration
{
  NSParameterAssert(configuration);
  return [[FBAgentLaunchStrategy strategyWithSimulator:self.simulator] launchAgent:configuration];
}

@end

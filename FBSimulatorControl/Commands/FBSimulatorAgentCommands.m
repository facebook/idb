/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorAgentCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator+Private.h"
#import "FBAgentLaunchStrategy.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBSimulatorAgentCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorAgentCommands

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

#pragma mark FBSimulatorAgentCommands Implementation

- (FBFuture<FBSimulatorAgentOperation *> *)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch
{
  NSParameterAssert(agentLaunch);
  return [[FBAgentLaunchStrategy strategyWithSimulator:self.simulator] launchAgent:agentLaunch];
}

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorAgentCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBAgentLaunchStrategy.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBSimulatorAgentCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorAgentCommands

+ (instancetype)commandsWithSimulator:(FBSimulator *)simulator
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

- (BOOL)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch error:(NSError **)error
{
  NSParameterAssert(agentLaunch);
  return [[FBAgentLaunchStrategy strategyWithSimulator:self.simulator] launchAgent:agentLaunch error:error] != nil;
}

- (BOOL)killAgent:(FBBinaryDescriptor *)agent error:(NSError **)error
{
  NSParameterAssert(agent);

  FBProcessInfo *process = [[[self.simulator
    launchdSimSubprocesses]
    filteredArrayUsingPredicate:[FBProcessFetcher processesForBinary:agent]]
    firstObject];

  if (!process) {
    return [[[FBSimulatorError
      describeFormat:@"Could not find an active process for %@", agent]
      inSimulator:self.simulator]
      failBool:error];
  }
  FBProcessTerminationStrategy *strategy = [FBProcessTerminationStrategy strategyWithProcessFetcher:self.simulator.processFetcher.processFetcher logger:self.simulator.logger];
  if (![strategy killProcess:process error:error]) {
    return [[[FBSimulatorError
      describeFormat:@"SIGKILL of Agent %@ of PID %d failed", agent, process.processIdentifier]
      inSimulator:self.simulator]
      failBool:error];
  }
  [self.simulator.eventSink agentDidTerminate:process expected:YES];
  return YES;
}

@end

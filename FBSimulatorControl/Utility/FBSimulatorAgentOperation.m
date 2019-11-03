/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorAgentOperation.h"

#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorProcessFetcher.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeSimulatorAgent = @"agent";

@interface FBSimulatorAgentOperation ()

@property (nonatomic, weak, nullable, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorAgentOperation

@synthesize exitCode = _exitCode;
@synthesize processIdentifier = _processIdentifier;

#pragma mark Initializers

+ (FBFuture<FBSimulatorAgentOperation *> *)operationWithSimulator:(FBSimulator *)simulator configuration:(FBAgentLaunchConfiguration *)configuration stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr launchFuture:(FBFuture<NSNumber *> *)launchFuture processStatusFuture:(FBFuture<NSNumber *> *)processStatusFuture
{
  return [launchFuture
    onQueue:simulator.workQueue map:^(NSNumber *processIdentifierNumber) {
      pid_t processIdentifier = processIdentifierNumber.intValue;
      return [[self alloc] initWithSimulator:simulator configuration:configuration stdOut:stdOut stdErr:stdErr processIdentifier:processIdentifier processStatusFuture:processStatusFuture];
    }];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBAgentLaunchConfiguration *)configuration stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr processIdentifier:(pid_t)processIdentifier processStatusFuture:(FBFuture<NSNumber *> *)processStatusFuture
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _configuration = configuration;
  _stdOut = stdOut;
  _stdErr = stdErr;
  _processIdentifier = processIdentifier;
  _processStatus = [[processStatusFuture
    onQueue:simulator.workQueue chain:^ FBFuture<NSNumber *> * (FBFuture<NSNumber *> *future) {
      FBFuture<NSNull *> *teardown = future.result
        ? [self processDidTerminate:future.result.intValue]
        : [self processWasCancelled];
      return [teardown chainReplace:future];
    }]
    nameFormat:@"Completion of agent process %d", processIdentifier];
  _exitCode = [[processStatusFuture
    onQueue:simulator.asyncQueue map:^(NSNumber *statLocNumber) {
      int stat_loc = statLocNumber.intValue;
      if (WIFEXITED(stat_loc)) {
        return @(WEXITSTATUS(stat_loc));
      } else {
        return @(WTERMSIG(stat_loc));
      }
    }]
    nameFormat:@"Exit code of agent process %d", processIdentifier];

  return self;
}

+ (BOOL)isExpectedTerminationForStatLoc:(int)statLoc
{
  if (WIFEXITED(statLoc)) {
    return WEXITSTATUS(statLoc) == 0;
  }
  return NO;
}

#pragma mark Private

- (FBFuture<NSNull *> *)processDidTerminate:(int)stat_loc
{
  FBFuture<NSNull *> *teardown = [self performTeardown];
  [self.simulator.eventSink agentDidTerminate:self statLoc:stat_loc];
  return teardown;
}

- (FBFuture<NSNull *> *)processWasCancelled
{
  FBFuture<NSNull *> *teardown = [self performTeardown];

  // When cancelled, the process is may still be alive. Therefore, the process needs to be terminated to fulfill the cancellation contract.
  [[FBProcessTerminationStrategy
    strategyWithProcessFetcher:self.simulator.processFetcher.processFetcher workQueue:self.simulator.workQueue logger:self.simulator.logger]
    killProcessIdentifier:self.processIdentifier];

  return teardown;
}

- (FBFuture<NSNull *> *)performTeardown
{
  // Tear down the other resources.
  return [[FBFuture
    futureWithFutures:@[
      [self.stdOut detach] ?: FBFuture.empty,
      [self.stdErr detach] ?: FBFuture.empty,
    ]]
    mapReplace:NSNull.null];
}

#pragma mark FBiOSTargetContinuation

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeSimulatorAgent;
}

- (FBFuture<NSNull *> *)completed
{
  return [self.exitCode mapReplace:NSNull.null];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Agent Operation %@ | pid %d | State %@", self.configuration.shortDescription, self.processIdentifier, self.processStatus];
}

#pragma mark FBJSONSerialization

- (id)jsonSerializableRepresentation
{
  return @{
    @"config": self.configuration.jsonSerializableRepresentation,
    @"pid" : @(self.processIdentifier),
  };
}

@end

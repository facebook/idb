/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorLaunchedProcess.h"

#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBSimulatorLaunchedProcess ()

@property (nonatomic, weak, nullable, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBSimulatorLaunchedProcess

@synthesize statLoc = _statLoc;
@synthesize processIdentifier = _processIdentifier;

#pragma mark Initializers

+ (FBFuture<FBSimulatorLaunchedProcess *> *)processWithSimulator:(FBSimulator *)simulator configuration:(FBProcessSpawnConfiguration *)configuration stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr launchFuture:(FBFuture<NSNumber *> *)launchFuture processStatusFuture:(FBFuture<NSNumber *> *)processStatusFuture
{
  return [launchFuture
    onQueue:simulator.workQueue map:^(NSNumber *processIdentifierNumber) {
      pid_t processIdentifier = processIdentifierNumber.intValue;
      return [[self alloc] initWithSimulator:simulator configuration:configuration stdOut:stdOut stdErr:stdErr processIdentifier:processIdentifier processStatusFuture:processStatusFuture];
    }];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBProcessSpawnConfiguration *)configuration stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr processIdentifier:(pid_t)processIdentifier processStatusFuture:(FBFuture<NSNumber *> *)processStatusFuture
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
  _queue = simulator.asyncQueue;
  _statLoc = [[processStatusFuture
    onQueue:simulator.workQueue chain:^ FBFuture<NSNumber *> * (FBFuture<NSNumber *> *future) {
      FBFuture<NSNull *> *teardown = future.result
        ? [self processDidTerminate:future.result.intValue]
        : [self processWasCancelled];
      return [teardown chainReplace:future];
    }]
    nameFormat:@"Completion of agent process %d", processIdentifier];

  return self;
}

#pragma mark FBLaunchedProcess

- (FBFuture<NSNumber *> *)exitCode
{
  pid_t processIdentifier = self.processIdentifier;
  return [[self.statLoc
    onQueue:self.queue fmap:^(NSNumber *statLocNumber) {
      int statLoc = statLocNumber.intValue;
      if (WIFSIGNALED(statLoc)) {
        return [[FBControlCoreError
          describeFormat:@"No normal exit code, process %d died with signal %d", processIdentifier, WTERMSIG(statLoc)]
          failFuture];
      }
      return [FBFuture futureWithResult:@(WEXITSTATUS(statLoc))];
    }]
    nameFormat:@"Exit code of agent process %d", self.processIdentifier];
}

- (FBFuture<NSNumber *> *)signal
{
  pid_t processIdentifier = self.processIdentifier;
  return [[self.statLoc
    onQueue:self.queue fmap:^(NSNumber *statLocNumber) {
      int statLoc = statLocNumber.intValue;
      if (!WIFSIGNALED(statLoc)) {
        return [[FBControlCoreError
          describeFormat:@"Did not exit with a signal, process %d died with exit status %d", processIdentifier, WEXITSTATUS(statLoc)]
          failFuture];
      }
      return [FBFuture futureWithResult:@(WTERMSIG(statLoc))];
    }]
    nameFormat:@"Exit code of agent process %d", self.processIdentifier];
}

#pragma mark Private

- (FBFuture<NSNull *> *)processDidTerminate:(int)stat_loc
{
  FBFuture<NSNull *> *teardown = [self performTeardown];
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

#pragma mark FBiOSTargetOperation

- (FBFuture<NSNull *> *)completed
{
  return [self.exitCode mapReplace:NSNull.null];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Agent Operation %@ | pid %d | State %@", self.configuration.description, self.processIdentifier, self.statLoc];
}

@end

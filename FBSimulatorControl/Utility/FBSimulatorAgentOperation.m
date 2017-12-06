/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorAgentOperation.h"

#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBProcessOutput.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorProcessFetcher.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeSimulatorAgent = @"agent";

@interface FBSimulatorAgentOperation ()

@property (nonatomic, weak, nullable, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorAgentOperation

#pragma mark Initializers

+ (FBFuture<FBSimulatorAgentOperation *> *)operationWithSimulator:(FBSimulator *)simulator configuration:(FBAgentLaunchConfiguration *)configuration stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr launchFuture:(FBFuture<NSNumber *> *)launchFuture terminationFuture:(FBFuture<NSNumber *> *)terminationFuture
{
  return [[launchFuture
    onQueue:simulator.workQueue fmap:^(NSNumber *processIdentifierNumber) {
      FBProcessFetcher *fetcher = [FBProcessFetcher new];
      return [fetcher onQueue:simulator.asyncQueue processInfoFor:processIdentifierNumber.intValue timeout:FBControlCoreGlobalConfiguration.fastTimeout];
    }]
    onQueue:simulator.workQueue map:^(FBProcessInfo *process) {
      return [[self alloc] initWithSimulator:simulator configuration:configuration stdOut:stdOut stdErr:stdErr process:process terminationFuture:terminationFuture];
    }];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBAgentLaunchConfiguration *)configuration stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr process:(FBProcessInfo *)process terminationFuture:(FBFuture<NSNumber *> *)terminationFuture
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _configuration = configuration;
  _stdOut = stdOut;
  _stdErr = stdErr;
  _process = process;
  _future = [terminationFuture onQueue:simulator.workQueue notifyOfCompletion:^(FBFuture<NSNumber *> *future) {
    if (future.result) {
      [self processDidTerminate:future.result.intValue];
    } else {
      [self processWasCancelled];
    }
  }];

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

- (void)processDidTerminate:(int)stat_loc
{
  [self performTeardown];
  [self.simulator.eventSink agentDidTerminate:self statLoc:stat_loc];
}

- (void)processWasCancelled
{
  [self performTeardown];
  // When cancelled, the process is still alive. Therefore, the process needs to be terminated to fulfill the cancellation contract.
  [[FBProcessTerminationStrategy
    strategyWithProcessFetcher:self.simulator.processFetcher.processFetcher workQueue:self.simulator.workQueue logger:self.simulator.logger]
    killProcess:self.process];
}

- (void)performTeardown
{
  // Return early if nothing was actually launched.
  if (!self.process) {
    return;
  }

  // Tear down the other resources.
  [self.stdOut.completed cancel];
  [self.stdErr.completed cancel];
}

#pragma mark FBiOSTargetContinuation

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeSimulatorAgent;
}

- (FBFuture<NSNull *> *)completed
{
  return [self.future mapReplace:NSNull.null];
}

@end

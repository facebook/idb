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
#import "FBSimulatorEventSink.h"
#import "FBSimulatorProcessFetcher.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeSimulatorAgent = @"agent";

@interface FBSimulatorAgentOperation ()

@property (nonatomic, weak, nullable, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBFuture<FBProcessInfo *> *processInfoFuture;

@end

@implementation FBSimulatorAgentOperation

@synthesize exitCode = _exitCode;
@synthesize processIdentifier = _processIdentifier;

#pragma mark Initializers

+ (FBFuture<FBSimulatorAgentOperation *> *)operationWithSimulator:(FBSimulator *)simulator configuration:(FBAgentLaunchConfiguration *)configuration stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr launchFuture:(FBFuture<NSNumber *> *)launchFuture processStatusFuture:(FBFuture<NSNumber *> *)processStatusFuture
{
  return [launchFuture
    onQueue:simulator.workQueue map:^(NSNumber *processIdentifierNumber) {
      return [[self alloc] initWithSimulator:simulator configuration:configuration stdOut:stdOut stdErr:stdErr processIdentifier:processIdentifierNumber.intValue processStatusFuture:processStatusFuture];
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
  _processStatus = [processStatusFuture
    onQueue:simulator.workQueue chain:^ FBFuture<NSNumber *> * (FBFuture<NSNumber *> *future) {
      FBFuture<NSNull *> *teardown = future.result
        ? [self processDidTerminate:future.result.intValue]
        : [self processWasCancelled];
      return [teardown fmapReplace:future];
    }];
  _exitCode = [processStatusFuture
    onQueue:simulator.asyncQueue map:^(NSNumber *statLocNumber) {
      int stat_loc = statLocNumber.intValue;
      if (WIFEXITED(stat_loc)) {
        return @(WEXITSTATUS(stat_loc));
      } else {
        return @(WTERMSIG(stat_loc));
      }
    }];
  _processInfoFuture = [[FBProcessFetcher.new
    onQueue:simulator.asyncQueue processInfoFor:processIdentifier timeout:FBControlCoreGlobalConfiguration.fastTimeout]
    rephraseFailure:@"Could not fetch process info for pid %d with configuration %@", processIdentifier, configuration];

  return self;
}

+ (BOOL)isExpectedTerminationForStatLoc:(int)statLoc
{
  if (WIFEXITED(statLoc)) {
    return WEXITSTATUS(statLoc) == 0;
  }
  return NO;
}

#pragma mark Public

- (FBProcessInfo *)processInfo
{
  return self.processInfoFuture.result;
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
  FBProcessInfo *processInfo = self.processInfo;
  if (processInfo) {
    [[FBProcessTerminationStrategy
      strategyWithProcessFetcher:self.simulator.processFetcher.processFetcher workQueue:self.simulator.workQueue logger:self.simulator.logger]
      killProcess:processInfo];
  }

  return teardown;
}

- (FBFuture<NSNull *> *)performTeardown
{
  // Tear down the other resources.
  return [[FBFuture
    futureWithFutures:@[
      [self.stdOut detach] ?: [FBFuture futureWithResult:NSNull.null],
      [self.stdErr detach] ?: [FBFuture futureWithResult:NSNull.null],
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
  return [NSString stringWithFormat:@"Agent Operation %@ | pid %d | State %@", self.configuration, self.processIdentifier, self.processStatus];
}

@end

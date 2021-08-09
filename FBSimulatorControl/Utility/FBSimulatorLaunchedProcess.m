/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorLaunchedProcess.h"

#import "FBSimulator+Private.h"
#import "FBSimulator.h"

@interface FBSimulatorLaunchedProcess ()

@property (nonatomic, weak, nullable, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBSimulatorLaunchedProcess

@synthesize configuration = _configuration;
@synthesize exitCode = _exitCode;
@synthesize processIdentifier = _processIdentifier;
@synthesize signal = _signal;
@synthesize statLoc = _statLoc;

#pragma mark Initializers

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBProcessSpawnConfiguration *)configuration processIdentifier:(pid_t)processIdentifier statLoc:(FBFuture<NSNumber *> *)statLoc exitCode:(FBFuture<NSNumber *> *)exitCode signal:(FBFuture<NSNumber *> *)signal
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _configuration = configuration;
  _processIdentifier = processIdentifier;
  _queue = simulator.asyncQueue;
  _exitCode = exitCode;
  _signal = signal;
  _statLoc = [[statLoc
    onQueue:simulator.workQueue chain:^ FBFuture<NSNumber *> * (FBFuture<NSNumber *> *future) {
      if (future.state == FBFutureStateCancelled) {
        return [self processWasCancelled:future];
      }
      return future;
    }]
    nameFormat:@"Completion of  process %d", processIdentifier];

  return self;
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo
{
  return [FBProcessSpawnCommandHelpers sendSignal:signo toProcess:self];
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo backingOffToKillWithTimeout:(NSTimeInterval)timeout logger:(id<FBControlCoreLogger>)logger
{
  return [FBProcessSpawnCommandHelpers sendSignal:signo backingOffToKillWithTimeout:timeout toProcess:self logger:logger];
}

#pragma mark Private

- (FBFuture<NSNumber *> *)processWasCancelled:(FBFuture<NSNumber *> *)statLocFuture
{
  // When cancelled, the process is may still be alive. Therefore, the process needs to be terminated to fulfill the cancellation contract.
  [[FBProcessTerminationStrategy
    strategyWithProcessFetcher:FBProcessFetcher.new workQueue:self.simulator.workQueue logger:self.simulator.logger]
    killProcessIdentifier:self.processIdentifier];

  return statLocFuture;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Simulator Process %@ | pid %d | State %@", self.configuration.description, self.processIdentifier, self.statLoc];
}

@end

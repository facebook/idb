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
  _statLoc = statLoc;

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

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Simulator Process %@ | pid %d | State %@", self.configuration.description, self.processIdentifier, self.statLoc];
}

@end

/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorApplicationOperation.h"

#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBSimulatorApplicationOperation ()

@property (nonatomic, weak, nullable, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorApplicationOperation

@synthesize completed = _completed;

#pragma mark Initializers

+ (FBFuture<FBSimulatorApplicationOperation *> *)operationWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationLaunchConfiguration *)configuration stdOut:(id<FBProcessFileOutput>)stdOut stdErr:(id<FBProcessFileOutput>)stdErr launchFuture:(FBFuture<NSNumber *> *)launchFuture
{
  return [launchFuture
    onQueue:simulator.workQueue map:^(NSNumber *processIdentifierNumber) {
      pid_t processIdentifier = processIdentifierNumber.intValue;
      FBFuture<NSNull *> *terminationFuture = [FBSimulatorApplicationOperation terminationFutureForSimulator:simulator processIdentifier:processIdentifier];
      FBSimulatorApplicationOperation *operation = [[self alloc] initWithSimulator:simulator configuration:configuration stdOut:stdOut stdErr:stdErr processIdentifier:processIdentifier terminationFuture:terminationFuture];
      [simulator.eventSink applicationDidLaunch:operation];
      return operation;
    }];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationLaunchConfiguration *)configuration stdOut:(id<FBProcessFileOutput>)stdOut stdErr:(id<FBProcessFileOutput>)stdErr processIdentifier:(pid_t)processIdentifier terminationFuture:(FBFuture<NSNull *> *)terminationFuture
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
  _completed = [terminationFuture
    onQueue:simulator.workQueue chain:^(FBFuture *future) {
      return [[self performTeardown] chainReplace:future];
    }];
  return self;
}

#pragma mark Helpers

+ (FBFuture<NSNull *> *)terminationFutureForSimulator:(FBSimulator *)simulator processIdentifier:(pid_t)processIdentifier
{
  return [[[FBDispatchSourceNotifier
    processTerminationFutureNotifierForProcessIdentifier:processIdentifier]
    mapReplace:NSNull.null]
    onQueue:simulator.workQueue respondToCancellation:^{
      [[FBProcessTerminationStrategy
        strategyWithProcessFetcher:simulator.processFetcher.processFetcher workQueue:simulator.workQueue logger:simulator.logger]
        killProcessIdentifier:processIdentifier];
      return FBFuture.empty;
    }];
}

#pragma mark FBiOSTargetContinuation

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeApplicationLaunch;
}

#pragma mark FBLaunchedProcess

- (FBFuture<NSNull *> *)exitCode
{
  return [self.completed mapReplace:@0];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Application Operation %@ | pid %d | State %@", self.configuration.shortDescription, self.processIdentifier, self.completed];
}

#pragma mark FBJSONSerialization

- (id)jsonSerializableRepresentation
{
  return @{
    @"config": self.configuration.jsonSerializableRepresentation,
    @"pid" : @(self.processIdentifier),
  };
}

#pragma mark Private

- (FBFuture<NSNull *> *)performTeardown
{
  [self.simulator.eventSink applicationDidTerminate:self expected:NO];

  return [[FBFuture
    futureWithFutures:@[
      [self.stdOut stopReading],
      [self.stdErr stopReading],
    ]]
    mapReplace:NSNull.null];
}

@end

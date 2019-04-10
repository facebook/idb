/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorApplicationOperation.h"

#import "FBSimulator.h"
#import "FBSimulatorEventSink.h"

@interface FBSimulatorApplicationOperation ()

@property (nonatomic, weak, nullable, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBFuture<FBProcessInfo *> *processInfoFuture;

@end

@implementation FBSimulatorApplicationOperation

@synthesize completed = _completed;

#pragma mark Initializers

+ (FBFuture<FBSimulatorApplicationOperation *> *)operationWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationLaunchConfiguration *)configuration stdOut:(id<FBProcessFileOutput>)stdOut stdErr:(id<FBProcessFileOutput>)stdErr launchFuture:(FBFuture<NSNumber *> *)launchFuture
{
  return [launchFuture
    onQueue:simulator.workQueue map:^(NSNumber *processIdentifierNumber) {
      pid_t processIdentifier = processIdentifierNumber.intValue;
      FBFuture<FBProcessInfo *> *processInfoFuture = [[FBProcessFetcher
        obtainProcessInfoForProcessIdentifierInBackground:processIdentifierNumber.intValue timeout:FBControlCoreGlobalConfiguration.fastTimeout]
        rephraseFailure:@"Could not fetch process info for App %@ with configuration %@", processIdentifierNumber, configuration];
      FBFuture<NSNull *> *terminationFuture = [FBSimulatorApplicationOperation terminationFutureForSimulator:simulator processIdentifier:processIdentifier];
      FBSimulatorApplicationOperation *operation = [[self alloc] initWithSimulator:simulator configuration:configuration stdOut:stdOut stdErr:stdErr processIdentifier:processIdentifier processInfoFuture:processInfoFuture terminationFuture:terminationFuture];
      [simulator.eventSink applicationDidLaunch:operation];
      return operation;
    }];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationLaunchConfiguration *)configuration stdOut:(id<FBProcessFileOutput>)stdOut stdErr:(id<FBProcessFileOutput>)stdErr processIdentifier:(pid_t)processIdentifier processInfoFuture:(FBFuture<FBProcessInfo *> *)processInfoFuture terminationFuture:(FBFuture<NSNull *> *)terminationFuture
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
      return [[self performTeardown] fmapReplace:future];
    }];
  _processInfoFuture = processInfoFuture;

  return self;
}

#pragma mark Helpers

+ (FBFuture<NSNull *> *)terminationFutureForSimulator:(FBSimulator *)simulator processIdentifier:(pid_t)processIdentifier
{
  FBMutableFuture<NSNull *> *future = FBMutableFuture.future;
  FBDispatchSourceNotifier *notifier = nil;
  notifier = [FBDispatchSourceNotifier
    processTerminationNotifierForProcessIdentifier:processIdentifier
    queue:simulator.asyncQueue
    handler:^(FBDispatchSourceNotifier *_) {
      [future resolveWithResult:NSNull.null];
    }];
  return [future
    onQueue:simulator.workQueue respondToCancellation:^{
      [notifier terminate];
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

#pragma mark Properties

- (FBProcessInfo *)processInfo
{
  return self.processInfoFuture.result;
}

#pragma mark FBiOSTargetContinuation

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeApplicationLaunch;
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

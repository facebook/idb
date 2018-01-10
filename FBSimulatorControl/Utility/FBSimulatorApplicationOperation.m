/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorApplicationOperation.h"

#import "FBSimulator.h"
#import "FBSimulatorEventSink.h"

@interface FBSimulatorApplicationOperation ()

@property (nonatomic, weak, nullable, readonly) FBSimulator *simulator;
@property (nonatomic, strong, nullable, readwrite) FBDispatchSourceNotifier *notifier;

@end

@implementation FBSimulatorApplicationOperation

@synthesize completed = _completed;

#pragma mark Initializers

+ (FBFuture<FBSimulatorApplicationOperation *> *)operationWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationLaunchConfiguration *)configuration launchFuture:(FBFuture<NSNumber *> *)launchFuture
{
  return [[launchFuture
    onQueue:simulator.workQueue fmap:^(NSNumber *processIdentifierNumber) {
      FBProcessFetcher *fetcher = [FBProcessFetcher new];
      return [fetcher onQueue:simulator.asyncQueue processInfoFor:processIdentifierNumber.intValue timeout:FBControlCoreGlobalConfiguration.fastTimeout];
    }]
    onQueue:simulator.workQueue map:^(FBProcessInfo *process) {
      FBFuture<NSNull *> *terminationFuture = [FBSimulatorApplicationOperation terminationFutureForSimulator:simulator processIdentifier:process.processIdentifier];
      return [[self alloc] initWithSimulator:simulator configuration:configuration process:process terminationFuture:terminationFuture];
    }];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationLaunchConfiguration *)configuration process:(FBProcessInfo *)process terminationFuture:(FBFuture<NSNull *> *)terminationFuture
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _configuration = configuration;
  _process = process;
  _completed = [terminationFuture
    onQueue:simulator.workQueue
    notifyOfCompletion:^(FBFuture *future) {
      [simulator.eventSink applicationDidTerminate:self expected:NO];
    }];

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
    onQueue:simulator.workQueue
    respondToCancellation:^{
      [notifier terminate];
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

#pragma mark FBiOSTargetContinuation

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeApplicationLaunch;
}

@end

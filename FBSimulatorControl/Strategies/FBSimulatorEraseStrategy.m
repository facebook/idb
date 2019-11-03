/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorEraseStrategy.h"

#import <CoreSimulator/SimDevice.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorSet.h"
#import "FBSimulatorTerminationStrategy.h"

@interface FBSimulatorEraseStrategy ()

@property (nonatomic, weak, readonly) FBSimulatorSet *set;
@property (nonatomic, copy, readonly) FBSimulatorControlConfiguration *configuration;
@property (nonatomic, strong, readonly) FBSimulatorProcessFetcher *processFetcher;
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBSimulatorEraseStrategy

#pragma mark Initializers

+ (instancetype)strategyForSet:(FBSimulatorSet *)set;
{
  return [[self alloc] initWithSet:set configuration:set.configuration processFetcher:set.processFetcher logger:set.logger];
}

- (instancetype)initWithSet:(FBSimulatorSet *)set configuration:(FBSimulatorControlConfiguration *)configuration processFetcher:(FBSimulatorProcessFetcher *)processFetcher logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;
  _configuration = configuration;
  _processFetcher = processFetcher;
  _logger = logger;

  return self;
}

#pragma mark Public

- (FBFuture<NSArray<FBSimulator *> *> *)eraseSimulators:(NSArray<FBSimulator *> *)simulators
{
  // Confirm that the Simulators belong to the Set.
  for (FBSimulator *simulator in simulators) {
    if (simulator.set != self.set) {
      return [[[FBSimulatorError
        describeFormat:@"Simulator's set %@ is not %@, cannot erase", simulator.set, self]
        inSimulator:simulator]
        failFuture];
    }
  }

  return [[self.terminationStrategy
    killSimulators:simulators]
    onQueue:dispatch_get_main_queue() fmap:^(NSArray<FBSimulator *> *result) {
      NSMutableArray<FBFuture<FBSimulator *> *> *futures = [NSMutableArray array];
      for (FBSimulator *simulator in result) {
        [futures addObject:[self eraseContentsAndSettings:simulator]];
      }
      return [FBFuture futureWithFutures:futures];
    }];
}

#pragma mark Private

- (FBFuture<FBSimulator *> *)eraseContentsAndSettings:(FBSimulator *)simulator
{
  [self.logger logFormat:@"Erasing %@", simulator];
  FBMutableFuture<FBSimulator *> *future = FBMutableFuture.future;
  [simulator.device
    eraseContentsAndSettingsAsyncWithCompletionQueue:simulator.workQueue
    completionHandler:^(NSError *error){
      if (error) {
        [future resolveWithError:error];
      } else {
        [self.logger logFormat:@"Erased %@", simulator];
        [future resolveWithResult:simulator];
      }
    }];
  return future;
}

- (FBSimulatorTerminationStrategy *)terminationStrategy
{
  return [FBSimulatorTerminationStrategy strategyForSet:self.set];
}

@end

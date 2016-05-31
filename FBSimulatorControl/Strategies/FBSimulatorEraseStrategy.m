/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
@property (nonatomic, strong, readonly) FBProcessFetcher *processFetcher;
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBSimulatorEraseStrategy

+ (instancetype)strategyForSet:(FBSimulatorSet *)set;
{
  return [[self alloc] initWithSet:set configuration:set.configuration processFetcher:set.processFetcher logger:set.logger];
}

- (instancetype)initWithSet:(FBSimulatorSet *)set configuration:(FBSimulatorControlConfiguration *)configuration processFetcher:(FBProcessFetcher *)processFetcher logger:(id<FBControlCoreLogger>)logger
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

- (nullable NSArray<FBSimulator *> *)eraseSimulators:(NSArray<FBSimulator *> *)simulators error:(NSError **)error
{
  // Confirm that the Simulators belong to the Set.
  for (FBSimulator *simulator in simulators) {
    if (simulator.set != self.set) {
      return [[[FBSimulatorError
        describeFormat:@"Simulator's set %@ is not %@, cannot erase", simulator.set, self]
        inSimulator:simulator]
        fail:error];
    }
  }

  // Kill the Simulators before erasing them.
  NSError *innerError = nil;
  if (![self.terminationStrategy killSimulators:simulators error:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  // Then Erase them.
  for (FBSimulator *simulator in simulators) {
    [self.logger logFormat:@"Erasing %@", simulator];
    if (![simulator.device eraseContentsAndSettingsWithError:&innerError]) {
      return [FBSimulatorError failWithError:innerError errorOut:error];
    }
    [self.logger logFormat:@"Erased %@", simulator];
  }
  return simulators;
}

#pragma mark Private

- (FBSimulatorTerminationStrategy *)terminationStrategy
{
  return [FBSimulatorTerminationStrategy strategyForSet:self.set];
}

@end

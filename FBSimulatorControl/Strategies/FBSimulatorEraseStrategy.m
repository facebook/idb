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
#import "FBSimulatorTerminationStrategy.h"

@interface FBSimulatorEraseStrategy ()

@property (nonatomic, copy, readonly) FBSimulatorControlConfiguration *configuration;
@property (nonatomic, strong, readonly) FBProcessFetcher *processFetcher;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBSimulatorEraseStrategy

+ (instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration processFetcher:(FBProcessFetcher *)processFetcher logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithConfiguration:configuration processFetcher:processFetcher logger:logger];
}

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration processFetcher:(FBProcessFetcher *)processFetcher logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _processFetcher = processFetcher;
  _logger = logger;

  return self;
}

- (nullable NSArray<FBSimulator *> *)eraseSimulators:(NSArray<FBSimulator *> *)simulators error:(NSError **)error
{
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
  return [FBSimulatorTerminationStrategy withConfiguration:self.configuration processFetcher:self.processFetcher logger:self.logger];
}

@end

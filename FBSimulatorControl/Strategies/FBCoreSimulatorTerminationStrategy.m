/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBCoreSimulatorTerminationStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import "FBProcessFetcher+Simulators.h"
#import "FBProcessTerminationStrategy.h"

@interface FBCoreSimulatorTerminationStrategy ()

@property (nonatomic, strong, readonly) FBProcessFetcher *processFetcher;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) FBProcessTerminationStrategy *processTerminationStrategy;

@end

@implementation FBCoreSimulatorTerminationStrategy

#pragma mark Initializers

+ (instancetype)withProcessFetcher:(FBProcessFetcher *)processFetcher logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithprocessFetcher:processFetcher logger:logger];
}

- (instancetype)initWithprocessFetcher:(FBProcessFetcher *)processFetcher logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processFetcher = processFetcher;
  _logger = logger;
  _processTerminationStrategy = [FBProcessTerminationStrategy withProcessFetcher:processFetcher logger:logger];

  return self;
}

#pragma mark Public

- (BOOL)killSpuriousCoreSimulatorServicesWithError:(NSError **)error
{
  NSPredicate *predicate = [NSCompoundPredicate notPredicateWithSubpredicate:
    [FBProcessFetcher coreSimulatorProcessesForCurrentXcode]
  ];
  NSArray *processes = [[self.processFetcher coreSimulatorServiceProcesses] filteredArrayUsingPredicate:predicate];

  if (processes.count == 0) {
    [self.logger.debug log:@"There are no spurious CoreSimulatorService processes to kill"];
    return YES;
  }

  [self.logger.debug logFormat:@"Killing Spurious CoreSimulatorServices %@", [FBCollectionInformation oneLineDescriptionFromArray:processes atKeyPath:@"debugDescription"]];
  return [self.processTerminationStrategy killProcesses:processes error:error];
}

@end

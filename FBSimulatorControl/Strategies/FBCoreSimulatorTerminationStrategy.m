/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCoreSimulatorTerminationStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulatorProcessFetcher.h"

@interface FBCoreSimulatorTerminationStrategy ()

@property (nonatomic, strong, readonly) FBSimulatorProcessFetcher *processFetcher;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) FBProcessTerminationStrategy *processTerminationStrategy;

@end

@implementation FBCoreSimulatorTerminationStrategy

#pragma mark Initializers

+ (instancetype)strategyWithProcessFetcher:(FBSimulatorProcessFetcher *)processFetcher workQueue:(dispatch_queue_t)workQueue logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithProcessFetcher:processFetcher workQueue:workQueue logger:logger];
}

- (instancetype)initWithProcessFetcher:(FBSimulatorProcessFetcher *)processFetcher workQueue:(dispatch_queue_t)workQueue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processFetcher = processFetcher;
  _logger = logger;
  _processTerminationStrategy = [FBProcessTerminationStrategy strategyWithProcessFetcher:processFetcher.processFetcher workQueue:workQueue logger:logger];

  return self;
}

#pragma mark Public

- (BOOL)killSpuriousCoreSimulatorServicesWithError:(NSError **)error
{
  NSPredicate *predicate = [NSCompoundPredicate notPredicateWithSubpredicate:
    FBSimulatorProcessFetcher.coreSimulatorProcessesForCurrentXcode
  ];
  NSArray *processes = [[self.processFetcher coreSimulatorServiceProcesses] filteredArrayUsingPredicate:predicate];

  if (processes.count == 0) {
    [self.logger.debug log:@"There are no spurious CoreSimulatorService processes to kill"];
    return YES;
  }

  [self.logger.debug logFormat:@"Killing Spurious CoreSimulatorServices %@", [FBCollectionInformation oneLineDescriptionFromArray:processes atKeyPath:@"debugDescription"]];
  return [[self.processTerminationStrategy killProcesses:processes] await:error] != nil;
}

@end

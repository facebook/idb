/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBCoreSimulatorTerminationStrategy.h"

#import "FBCollectionDescriptions.h"
#import "FBSimulatorLogger.h"
#import "FBProcessTerminationStrategy.h"
#import "FBProcessQuery+Simulators.h"

@interface FBCoreSimulatorTerminationStrategy ()

@property (nonatomic, strong, readonly) FBProcessQuery *processQuery;
@property (nonatomic, strong, readonly) id<FBSimulatorLogger> logger;
@property (nonatomic, strong, readonly) FBProcessTerminationStrategy *processTerminationStrategy;

@end

@implementation FBCoreSimulatorTerminationStrategy

#pragma mark Initializers

+ (instancetype)withProcessQuery:(FBProcessQuery *)processQuery logger:(id<FBSimulatorLogger>)logger
{
  return [[self alloc] initWithProcessQuery:processQuery logger:logger];
}

- (instancetype)initWithProcessQuery:(FBProcessQuery *)processQuery logger:(id<FBSimulatorLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processQuery = processQuery;
  _logger = logger;
  _processTerminationStrategy = [FBProcessTerminationStrategy withProcessKilling:processQuery logger:logger];

  return self;
}

#pragma mark Public

- (BOOL)killSpuriousCoreSimulatorServicesWithError:(NSError **)error
{
  NSPredicate *predicate = [NSCompoundPredicate notPredicateWithSubpredicate:
    [FBProcessQuery coreSimulatorProcessesForCurrentXcode]
  ];
  NSArray *processes = [[self.processQuery coreSimulatorServiceProcesses] filteredArrayUsingPredicate:predicate];

  if (processes.count == 0) {
    [self.logger.debug log:@"There are no spurious CoreSimulatorService processes to kill"];
    return YES;
  }

  [self.logger.debug logFormat:@"Killing Spurious CoreSimulatorServices %@", [FBCollectionDescriptions oneLineDescriptionFromArray:processes atKeyPath:@"debugDescription"]];
  return [self.processTerminationStrategy killProcesses:processes error:error];
}

@end

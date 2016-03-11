/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorPool.h"
#import "FBSimulatorPool+Private.h"

#import <FBControlCore/FBControlCoreLogger.h>

#import "FBCoreSimulatorNotifier.h"
#import "FBCoreSimulatorTerminationStrategy.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction.h"
#import "FBSimulatorPredicates.h"
#import "FBSimulatorSet.h"
#import "FBSimulatorTerminationStrategy.h"

@implementation FBSimulatorPool

#pragma mark - Initializers

+ (instancetype)poolWithSet:(FBSimulatorSet *)set logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithSet:set logger:logger];
}

- (instancetype)initWithSet:(FBSimulatorSet *)set logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;
  _logger = logger;
  _allocatedUDIDs = [NSMutableOrderedSet new];
  _allocationOptions = [NSMutableDictionary dictionary];

  return self;
}

#pragma mark - Public Methods

- (FBSimulator *)allocateSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration options:(FBSimulatorAllocationOptions)options error:(NSError **)error;
{
  NSError *innerError = nil;
  FBSimulator *simulator = [self obtainSimulatorWithConfiguration:configuration options:options error:&innerError];
  if (!simulator) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  if (![self prepareSimulatorForUsage:simulator configuration:configuration options:options error:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  [self pushAllocation:simulator options:options];
  return simulator;
}

- (BOOL)freeSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  FBSimulatorAllocationOptions options = [self popAllocation:simulator];

  // Killing is a pre-requesite for deleting/erasing
  NSError *innerError = nil;
  if (![self.set killSimulator:simulator error:&innerError]) {
    return [[[[[FBSimulatorError
      describe:@"Failed to Free Device in Killing Device"]
      causedBy:innerError]
      inSimulator:simulator]
      logger:self.logger]
      failBool:error];
  }

  // When Deleting on Free, there's no point in erasing first, so return early.
  BOOL deleteOnFree = (options & FBSimulatorAllocationOptionsDeleteOnFree) == FBSimulatorAllocationOptionsDeleteOnFree;
  if (deleteOnFree) {
    if (![self.set deleteSimulator:simulator error:&innerError]) {
      return [[[[[FBSimulatorError
        describe:@"Failed to Free Device in Deleting Device"]
        causedBy:innerError]
        inSimulator:simulator]
        logger:self.logger]
        failBool:error];
    }
    return YES;
  }

  BOOL eraseOnFree = (options & FBSimulatorAllocationOptionsEraseOnFree) == FBSimulatorAllocationOptionsEraseOnFree;
  if (eraseOnFree) {
    if (![simulator eraseWithError:&innerError]) {
      return [[[[[FBSimulatorError
        describe:@"Failed to Free Device in Erasing Device"]
        causedBy:innerError]
        inSimulator:simulator]
        logger:self.logger]
        failBool:error];
    }
    return YES;
  }

  return YES;
}

- (BOOL)simulatorIsAllocated:(FBSimulator *)simulator
{
  return [self.allocatedUDIDs containsObject:simulator.udid];
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [self shortDescription];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Set: %@ | Allocated %@",
    self.set.debugDescription,
    self.allocatedSimulators.description
  ];
}

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"Set: %@ | Allocated %@",
    self.set.description,
    self.allocatedSimulators.description
  ];
}

#pragma mark Properties

- (NSArray *)allocatedSimulators
{
  return [self.set.allSimulators filteredArrayUsingPredicate:[FBSimulatorPredicates allocatedByPool:self]];
}

- (NSArray *)unallocatedSimulators
{
  return [self.set.allSimulators filteredArrayUsingPredicate:[FBSimulatorPredicates unallocatedByPool:self]];
}

#pragma mark - Private

- (FBSimulator *)obtainSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration options:(FBSimulatorAllocationOptions)options error:(NSError **)error
{
  NSError *innerError = nil;
  if (![configuration checkRuntimeRequirementsReturningError:&innerError]) {
    return [[[[FBSimulatorError
      describe:@"Current Runtime environment does not support Simulator Configuration"]
      causedBy:innerError]
      logger:self.logger]
      fail:error];
  }

  BOOL reuse = (options & FBSimulatorAllocationOptionsReuse) == FBSimulatorAllocationOptionsReuse;
  if (reuse) {
    FBSimulator *simulator = [self findUnallocatedSimulatorWithConfiguration:configuration];
    if (simulator) {
      [self.logger.debug logFormat:@"Found unallocated simulator %@ matching %@", simulator.udid, configuration];
      return simulator;
    }
  }

  BOOL create = (options & FBSimulatorAllocationOptionsCreate) == FBSimulatorAllocationOptionsCreate;
  if (!create) {
    return [[[FBSimulatorError
      describeFormat:@"Could not obtain a simulator as the options don't allow creation"]
      logger:self.logger]
      fail:error];
  }
  return [self.set createSimulatorWithConfiguration:configuration error:error];
}

- (FBSimulator *)findUnallocatedSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration
{
  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [FBSimulatorPredicates unallocatedByPool:self],
    [FBSimulatorPredicates configuration:configuration]
  ]];
  return [[self.set.allSimulators filteredArrayUsingPredicate:predicate] firstObject];
}

- (BOOL)prepareSimulatorForUsage:(FBSimulator *)simulator configuration:(FBSimulatorConfiguration *)configuration options:(FBSimulatorAllocationOptions)options error:(NSError **)error
{
  [self.logger.debug logFormat:@"Preparing Simulator %@ for usage", simulator.udid];
  NSError *innerError = nil;

  // In order to erase, the device *must* be shutdown first.
  BOOL shutdown = (options & FBSimulatorAllocationOptionsShutdownOnAllocate) == FBSimulatorAllocationOptionsShutdownOnAllocate;
  BOOL erase = (options & FBSimulatorAllocationOptionsEraseOnAllocate) == FBSimulatorAllocationOptionsEraseOnAllocate;
  BOOL reuse = (options & FBSimulatorAllocationOptionsReuse) == FBSimulatorAllocationOptionsReuse;
  BOOL enablePersistence = (options & FBSimulatorAllocationOptionsPersistHistory) == FBSimulatorAllocationOptionsPersistHistory;

  // Shutdown first.
  if (shutdown || erase) {
    [self.logger.debug logFormat:@"Shutting down Simulator %@", simulator.udid];
    if (![self.set killSimulator:simulator error:&innerError]) {
      return [[[[[FBSimulatorError
        describe:@"Failed to kill a Simulator when allocating it"]
        causedBy:innerError]
        inSimulator:simulator]
        logger:self.logger]
        failBool:error];
    }
  }

  // Only erase if the simulator was allocated with reuse, otherwise it is a fresh Simulator that won't need erasing.
  if (reuse && erase) {
    [self.logger.debug logFormat:@"Erasing Simulator %@", simulator.udid];
    if (![simulator eraseWithError:&innerError]) {
      return [[[[[FBSimulatorError
        describe:@"Failed to erase a Simulator when allocating it"]
        causedBy:innerError]
        inSimulator:simulator]
        logger:self.logger]
        failBool:error];
    }
    [self.logger.debug logFormat:@"Shutting down Simulator after erase %@", simulator.udid];
    if (![simulator.simDeviceWrapper shutdownWithError:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }
  }

  // Enable/Disable Persistence
  simulator.historyGenerator.peristenceEnabled = enablePersistence;

  return YES;
}

- (void)pushAllocation:(FBSimulator *)simulator options:(FBSimulatorAllocationOptions)options
{
  NSParameterAssert(simulator);
  NSParameterAssert(![self.allocatedUDIDs containsObject:simulator.udid]);
  NSParameterAssert(!self.allocationOptions[simulator.udid]);
  NSParameterAssert(simulator.pool == nil);

  simulator.pool = self;
  [self.allocatedUDIDs addObject:simulator.udid];
  self.allocationOptions[simulator.udid] = @(options);
}

- (FBSimulatorAllocationOptions)popAllocation:(FBSimulator *)simulator
{
  NSParameterAssert(simulator);
  NSParameterAssert([self.allocatedUDIDs containsObject:simulator.udid]);
  NSParameterAssert(self.allocationOptions[simulator.udid]);
  NSParameterAssert(simulator.pool == self);

  simulator.pool = nil;
  [self.allocatedUDIDs removeObject:simulator.udid];
  FBSimulatorAllocationOptions options = [self.allocationOptions[simulator.udid] unsignedIntegerValue];
  [self.allocationOptions removeObjectForKey:simulator.udid];
  return options;
}

@end

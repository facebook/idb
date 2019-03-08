/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorPool.h"
#import "FBSimulatorPool+Private.h"

#import <FBControlCore/FBControlCore.h>

#import "FBCoreSimulatorNotifier.h"
#import "FBCoreSimulatorTerminationStrategy.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorShutdownStrategy.h"
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

- (FBFuture<FBSimulator *> *)allocateSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration options:(FBSimulatorAllocationOptions)options
{
  return [[self
    obtainAndAllocateSimulatorWithConfiguration:configuration options:options]
    onQueue:self.set.workQueue fmap:^(FBSimulator *simulator) {
      return [self prepareSimulatorForUsage:simulator configuration:configuration options:options];
    }];
}

- (FBFuture<NSNull *> *)freeSimulator:(FBSimulator *)simulator
{
  FBSimulatorAllocationOptions options = [self popAllocation:simulator];
  dispatch_queue_t workQueue = simulator.workQueue;

  // Killing is a pre-requesite for deleting/erasing
  return [[[[self.set
    killSimulator:simulator]
    rephraseFailure:@"Failed to Free Device in Killing Device"]
    onQueue:workQueue fmap:^(id _) {
      BOOL deleteOnFree = (options & FBSimulatorAllocationOptionsDeleteOnFree) == FBSimulatorAllocationOptionsDeleteOnFree;
      if (deleteOnFree) {
        return [[[self.set
          deleteSimulator:simulator]
          rephraseFailure:@"Failed to Free Device in Deleting Device"]
          mapReplace:@YES];
      }
      return [FBFuture futureWithResult:@NO];
    }]
    onQueue:workQueue fmap:^ FBFuture<NSNull *> * (NSNumber *didDelete) {
      // Return-Early if we deleted, no point in erasing.
      if (didDelete.boolValue) {
        return [FBFuture futureWithResult:NSNull.null];
      }
      // Otherwise check we should delete, then do it.
      BOOL eraseOnFree = (options & FBSimulatorAllocationOptionsEraseOnFree) == FBSimulatorAllocationOptionsEraseOnFree;
      if (eraseOnFree) {
        return [[simulator
          erase]
          rephraseFailure:@"Failed to Free Device in Erasing Device"];
      }
      // Otherwise do-nothing
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

- (BOOL)simulatorIsAllocated:(FBSimulator *)simulator
{
  return [self.allocatedUDIDs containsObject:simulator.udid];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Set: %@ | Allocated %@",
    self.set.debugDescription,
    self.allocatedSimulators.description
  ];
}

#pragma mark Properties

- (NSArray<FBSimulator *> *)allocatedSimulators
{
  return [self.set.allSimulators filteredArrayUsingPredicate:[FBSimulatorPredicates allocatedByPool:self]];
}

- (NSArray<FBSimulator *> *)unallocatedSimulators
{
  return [self.set.allSimulators filteredArrayUsingPredicate:[FBSimulatorPredicates unallocatedByPool:self]];
}

#pragma mark - Private

- (FBFuture<FBSimulator *> *)obtainAndAllocateSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration options:(FBSimulatorAllocationOptions)options
{
  NSError *innerError = nil;
  if (![configuration checkRuntimeRequirementsReturningError:&innerError]) {
    return [[[[FBSimulatorError
      describe:@"Current Runtime environment does not support Simulator Configuration"]
      causedBy:innerError]
      logger:self.logger]
      failFuture];
  }

  BOOL reuse = (options & FBSimulatorAllocationOptionsReuse) == FBSimulatorAllocationOptionsReuse;
  if (reuse) {
    FBSimulator *simulator = [self findUnallocatedSimulatorWithConfiguration:configuration];
    if (simulator) {
      [self.logger.debug logFormat:@"Found unallocated simulator %@ matching %@", simulator.udid, configuration];
      [self pushAllocation:simulator options:options];
      return [FBFuture futureWithResult:simulator];
    }
  }

  BOOL create = (options & FBSimulatorAllocationOptionsCreate) == FBSimulatorAllocationOptionsCreate;
  if (!create) {
    return [[[FBSimulatorError
      describeFormat:@"Could not obtain a simulator as the options don't allow creation"]
      logger:self.logger]
      failFuture];
  }
  return [[self.set
    createSimulatorWithConfiguration:configuration]
    onQueue:self.set.workQueue map:^(FBSimulator *simulator) {
      [self pushAllocation:simulator options:options];
      return simulator;
    }];
}

- (FBSimulator *)findUnallocatedSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration
{
  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [FBSimulatorPredicates unallocatedByPool:self],
    [FBSimulatorPredicates configuration:configuration]
  ]];
  return [[self.set.allSimulators filteredArrayUsingPredicate:predicate] firstObject];
}

- (FBFuture<FBSimulator *> *)prepareSimulatorForUsage:(FBSimulator *)simulator configuration:(FBSimulatorConfiguration *)configuration options:(FBSimulatorAllocationOptions)options
{
  [self.logger.debug logFormat:@"Preparing Simulator %@ for usage", simulator.udid];

  // In order to erase, the device *must* be shutdown first.
  BOOL shutdown = (options & FBSimulatorAllocationOptionsShutdownOnAllocate) == FBSimulatorAllocationOptionsShutdownOnAllocate;
  BOOL erase = (options & FBSimulatorAllocationOptionsEraseOnAllocate) == FBSimulatorAllocationOptionsEraseOnAllocate;
  BOOL reuse = (options & FBSimulatorAllocationOptionsReuse) == FBSimulatorAllocationOptionsReuse;

  // Shutdown first.
  FBFuture<NSNull *> *future = (shutdown || erase)
    ? [[self.set killSimulator:simulator] rephraseFailure:@"Failed to kill a Simulator when allocating it"]
    : [FBFuture futureWithResult:NSNull.null];

  return [[future
    onQueue:simulator.workQueue fmap:^(id _) {
      if (reuse && erase) {
        [self.logger.debug logFormat:@"Erasing Simulator %@", simulator.udid];
        return [[[simulator
          erase]
          rephraseFailure:@"Failed to erase a Simulator when allocating it"]
          onQueue:simulator.workQueue fmap:^(id __) {
            return [simulator shutdown];
          }];
      }
      return [FBFuture futureWithResult:NSNull.null];
    }]
    mapReplace:simulator];
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

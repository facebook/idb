/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorDeletionStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorSet.h"
#import "FBSimulatorSet+Private.h"

@interface FBSimulatorDeletionStrategy ()

@property (nonatomic, weak, readonly) FBSimulatorSet *set;
@property (nonatomic, nullable, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBSimulatorDeletionStrategy

#pragma mark Initializers

+ (instancetype)strategyForSet:(FBSimulatorSet *)set
{
  return [[self alloc] initWithSet:set logger:set.logger];
}

- (instancetype)initWithSet:(FBSimulatorSet *)set logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;
  _logger = logger;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSArray<NSString *> *> *)deleteSimulators:(NSArray<FBSimulator *> *)simulators
{
   // Confirm that the Simulators belong to the set
  for (FBSimulator *simulator in simulators) {
    if (simulator.set != self.set) {
      return [[[FBSimulatorError
        describeFormat:@"Simulator's set %@ is not %@, cannot delete", simulator.set, self]
        inSimulator:simulator]
        failFuture];
    }
  }

  // Keep the UDIDs around for confirmation.
  // Start the deletion
  NSSet<NSString *> *deletedDeviceUDIDs = [NSSet setWithArray:[simulators valueForKey:@"udid"]];
  NSMutableArray<FBFuture<NSString *> *> *futures = [NSMutableArray array];
  for (FBSimulator *simulator in simulators) {
    [futures addObject:[self deleteSimulator:simulator]];
  }

  return [[FBFuture
    futureWithFutures:futures]
    onQueue:dispatch_get_main_queue() fmap:^(id _) {
      return [FBSimulatorDeletionStrategy confirmSimulatorsAreRemovedFromSet:self.set deletedDeviceUDIDs:deletedDeviceUDIDs];
    }];
}

#pragma mark Private

+ (FBFuture<NSArray<NSString *> *> *)confirmSimulatorsAreRemovedFromSet:(FBSimulatorSet *)set deletedDeviceUDIDs:(NSSet<NSString *> *)deletedDeviceUDIDs
{
  // Deleting the device from the set can still leave it around for a few seconds.
  // This could race with methods that may reallocate the newly-deleted device.
  // So we should wait for the device to no longer be present in the underlying set.
  return [[[FBFuture
    onQueue:dispatch_get_main_queue() resolveWhen:^BOOL{
      NSMutableSet<NSString *> *remainderSet = [NSMutableSet setWithSet:deletedDeviceUDIDs];
      [remainderSet intersectSet:[NSSet setWithArray:[set.allSimulators valueForKey:@"udid"]]];
      return remainderSet.count == 0;
    }]
    timeout:FBControlCoreGlobalConfiguration.regularTimeout waitingFor:@"Simulator to be removed from set"]
    mapReplace:deletedDeviceUDIDs.allObjects];
}

- (FBFuture<NSString *> *)deleteSimulator:(FBSimulator *)simulator
{
  // Get the Log Directory ahead of time as the Simulator will dissapear on deletion.
  NSString *coreSimulatorLogsDirectory = simulator.coreSimulatorLogsDirectory;
  dispatch_queue_t workQueue = simulator.workQueue;
  NSString *udid = simulator.udid;

  // Kill the Simulators before deleting them.
  [self.logger logFormat:@"Killing Simulator, in preparation for deletion %@", simulator];
  return [[[self.set
    killSimulator:simulator]
    onQueue:workQueue fmap:^(id _) {
      // Then follow through with the actual deletion of the Simulator, which will remove it from the set.
      [self.logger logFormat:@"Deleting Simulator %@", simulator];
      return [FBSimulatorDeletionStrategy onDeviceSet:self.set.deviceSet performDeletionOfDevice:simulator.device onQueue:simulator.asyncQueue];
    }]
    onQueue:workQueue doOnResolved:^(id _) {
      [self.logger logFormat:@"Simulator %@ Deleted", udid];

      // The Logfiles now need disposing of. 'erasing' a Simulator will cull the logfiles,
      // but deleting a Simulator will not. There's no sense in letting this directory accumilate files.
      if ([NSFileManager.defaultManager fileExistsAtPath:coreSimulatorLogsDirectory]) {
        [self.logger logFormat:@"Deleting Simulator Log Directory at %@", coreSimulatorLogsDirectory];
        NSError *error = nil;
        if ([NSFileManager.defaultManager removeItemAtPath:coreSimulatorLogsDirectory error:&error]) {
          [self.logger logFormat:@"Deleted Simulator Log Directory at %@", coreSimulatorLogsDirectory];
        } else {
          [self.logger.error logFormat:@"Failed to delete Simulator Log Directory %@: %@", coreSimulatorLogsDirectory, error];
        }
      }
    }];
}

+ (FBFuture<NSString *> *)onDeviceSet:(SimDeviceSet *)deviceSet performDeletionOfDevice:(SimDevice *)device onQueue:(dispatch_queue_t)queue
{
  NSString *udid = device.UDID.UUIDString;
  FBMutableFuture<NSString *> *future = FBMutableFuture.future;
  [deviceSet deleteDeviceAsync:device completionQueue:queue completionHandler:^(NSError *error) {
    if (error) {
      [future resolveWithError:error];
    } else {
      [future resolveWithResult:udid];
    }
  }];
  return future;
}

@end

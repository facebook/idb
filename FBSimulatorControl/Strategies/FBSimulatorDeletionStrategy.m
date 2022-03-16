/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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
#import "FBSimulatorSet+Private.h"
#import "FBSimulatorSet.h"
#import "FBSimulatorShutdownStrategy.h"

@implementation FBSimulatorDeletionStrategy

#pragma mark Public Methods

+ (FBFuture<NSNull *> *)delete:(FBSimulator *)simulator
{
  // Get the Log Directory ahead of time as the Simulator will dissapear on deletion.
  NSString *coreSimulatorLogsDirectory = simulator.coreSimulatorLogsDirectory;
  dispatch_queue_t workQueue = simulator.workQueue;
  NSString *udid = simulator.udid;
  FBSimulatorSet *set = simulator.set;

  // Kill the Simulators before deleting them.
  [simulator.logger logFormat:@"Killing Simulator, in preparation for deletion %@", simulator];
  return [[[[FBSimulatorShutdownStrategy
    shutdown:simulator]
    onQueue:workQueue fmap:^(id _) {
      // Then follow through with the actual deletion of the Simulator, which will remove it from the set.
      [simulator.logger logFormat:@"Deleting Simulator %@", simulator];
      return [FBSimulatorDeletionStrategy onDeviceSet:simulator.set.deviceSet performDeletionOfDevice:simulator.device onQueue:simulator.asyncQueue];
    }]
    onQueue:workQueue fmap:^(id _) {
      [simulator.logger logFormat:@"Simulator %@ Deleted", udid];

      // The Logfiles now need disposing of. 'erasing' a Simulator will cull the logfiles,
      // but deleting a Simulator will not. There's no sense in letting this directory accumilate files.
      if ([NSFileManager.defaultManager fileExistsAtPath:coreSimulatorLogsDirectory]) {
        [simulator.logger logFormat:@"Deleting Simulator Log Directory at %@", coreSimulatorLogsDirectory];
        NSError *error = nil;
        if ([NSFileManager.defaultManager removeItemAtPath:coreSimulatorLogsDirectory error:&error]) {
          [simulator.logger logFormat:@"Deleted Simulator Log Directory at %@", coreSimulatorLogsDirectory];
        } else {
          [simulator.logger.error logFormat:@"Failed to delete Simulator Log Directory %@: %@", coreSimulatorLogsDirectory, error];
        }
      }

      [simulator.logger logFormat:@"Confirming %@ has been removed from set", udid];
      return [FBSimulatorDeletionStrategy confirmSimulatorUDID:udid isRemovedFromSet:set];
    }]
    onQueue:workQueue doOnResolved:^(id _) {
      [simulator.logger logFormat:@"%@ has been removed from set", udid];
    }];
}

+ (FBFuture<NSNull *> *)deleteAll:(NSArray<FBSimulator *> *)simulators
{
  NSMutableArray<FBFuture<NSNull *> *> *futures = [NSMutableArray array];
  for (FBSimulator *simulator in simulators) {
    [futures addObject:[self delete:simulator]];
  }
  return [[FBFuture futureWithFutures:futures] mapReplace:NSNull.null];
}

#pragma mark Private

+ (FBFuture<NSNull *> *)confirmSimulatorUDID:(NSString *)udid isRemovedFromSet:(FBSimulatorSet *)set
{
  // Deleting the device from the set can still leave it around for a few seconds.
  // This could race with methods that may reallocate the newly-deleted device.
  // So we should wait for the device to no longer be present in the underlying set.
  return [[FBFuture
    onQueue:set.workQueue resolveWhen:^BOOL{
      NSSet<NSString *> *simulatorsInSet = [NSSet setWithArray:[set.allSimulators valueForKey:@"udid"]];
      return [simulatorsInSet containsObject:udid] == NO;
    }]
    timeout:FBControlCoreGlobalConfiguration.regularTimeout waitingFor:@"Simulator to be removed from set"];
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

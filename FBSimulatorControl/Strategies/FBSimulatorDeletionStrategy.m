/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorDeletionStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorSet.h"
#import "FBSimulatorSet+Private.h"
#import "FBSimulatorDiagnostics.h"

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
    timedOutIn:FBControlCoreGlobalConfiguration.regularTimeout]
    rephraseFailure:@"Timed out waiting for Simulators to dissapear from set."];
}

- (FBFuture<NSString *> *)deleteSimulator:(FBSimulator *)simulator
{
  // Get the Log Directory ahead of time as the Simulator will dissapear on deletion.
  NSString *coreSimulatorLogsDirectory = simulator.simulatorDiagnostics.coreSimulatorLogsDirectory;
  dispatch_queue_t workQueue = simulator.workQueue;
  NSString *udid = simulator.udid;

  // Kill the Simulators before deleting them.
  [self.logger logFormat:@"Killing Simulator, in preparation for deletion %@", simulator];
  return [[self.set
    killSimulator:simulator]
    onQueue:workQueue fmap:^(NSArray<FBSimulator *> *result) {
      // Then follow through with the actual deletion of the Simulator, which will remove it from the set.
      NSError *innerError = nil;
      [self.logger logFormat:@"Deleting Simulator %@", simulator];
      NSUInteger retryDelete = 3;
      do {
        if ([self.set.deviceSet deleteDevice:simulator.device error:&innerError]) {
          break;
        }
        // On Travis the deleteDevice operation sometimes fails:
        //   Domain=NSCocoaErrorDomain Code=513 "B4D-C0-F-F-E" couldn't be removed because you don't have permission to access it.
        // Inside the devicePath there's a device.plist which sometimes cannot be deleted. Probably some process still has an open
        // file handle to that file.
        BOOL shouldRetry = [innerError.domain isEqualToString:NSCocoaErrorDomain] && innerError.code == NSFileWriteNoPermissionError;
        if (!shouldRetry) {
          return [[[[[FBSimulatorError
            describe:@"Failed to delete simulator."]
            inSimulator:simulator]
            causedBy:innerError]
            logger:self.logger]
            failFuture];
        }
      } while (--retryDelete > 0);
      [self.logger logFormat:@"Simulator Deleted Successfully %@", simulator];

      // The Logfiles now need disposing of. 'erasing' a Simulator will cull the logfiles,
      // but deleting a Simulator will not. There's no sense in letting this directory accumilate files.
      if ([NSFileManager.defaultManager fileExistsAtPath:coreSimulatorLogsDirectory]) {
        [self.logger logFormat:@"Deleting Log Directory at %@", coreSimulatorLogsDirectory];
        if (![NSFileManager.defaultManager removeItemAtPath:coreSimulatorLogsDirectory error:&innerError]) {
          return [[[[FBSimulatorError
            describeFormat:@"Failed to delete Simulator Log Directory %@.", coreSimulatorLogsDirectory]
            causedBy:innerError]
            logger:self.logger]
            failFuture];
        }
        [self.logger logFormat:@"Deleted Log Directory at %@", coreSimulatorLogsDirectory];
      }
      return [FBFuture futureWithResult:udid];
    }];
}

@end

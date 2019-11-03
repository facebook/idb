/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorShutdownStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulator.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"

@interface FBSimulatorShutdownStrategy ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorShutdownStrategy

#pragma mark Initializers

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  return self;
}

#pragma mark Public Methdos

- (FBFuture<NSNull *> *)shutdown
{
  FBSimulator *simulator = self.simulator;
  id<FBControlCoreLogger> logger = self.simulator.logger;
  [logger.debug logFormat:@"Starting Safe Shutdown of %@", simulator.udid];

  // If the device is in a strange state, we should bail now
  if (simulator.state == FBiOSTargetStateUnknown) {
    return [[[[FBSimulatorError
      describe:@"Failed to prepare simulator for usage as it is in an unknown state"]
      inSimulator:simulator]
      logger:logger]
      failFuture];
  }

  // Calling shutdown when already shutdown should be avoided (if detected).
  if (simulator.state == FBiOSTargetStateShutdown) {
    [logger.debug logFormat:@"Shutdown of %@ succeeded as it is already shutdown", simulator.udid];
    return FBFuture.empty;
  }

  // Xcode 7 has a 'Creating' step that we should wait on before confirming the simulator is ready.
  // On many occasions this is the case as we wait for the Simulator to be usable.
  if (simulator.state == FBiOSTargetStateCreating) {
    return [FBSimulatorShutdownStrategy transitionCreatingToShutdown:simulator];
  }

  // The error code for 'Unable to shutdown device in current state: Shutdown'
  // can be safely ignored since these codes confirm that the simulator is already shutdown.
  return [FBSimulatorShutdownStrategy shutdownSimulator:simulator];
}

+ (NSInteger)errorCodeForShutdownWhenShuttingDown
{
  if (FBXcodeConfiguration.isXcode9OrGreater) {
    return 164;
  }
  return 163;
}

+ (FBFuture<NSNull *> *)shutdownSimulator:(FBSimulator *)simulator
{
  FBMutableFuture<NSNull *> *future = FBMutableFuture.future;
  id<FBControlCoreLogger> logger = simulator.logger;
  NSInteger errorCodeForShutdownWhenShuttingDown = FBSimulatorShutdownStrategy.errorCodeForShutdownWhenShuttingDown;

  [logger.debug logFormat:@"Shutting down Simulator %@", simulator.udid];
  [simulator.device
    shutdownAsyncWithCompletionQueue:simulator.asyncQueue completionHandler:^(NSError *error){
      if (error && error.code == errorCodeForShutdownWhenShuttingDown) {
        [logger logFormat:@"Got Error Code %lu from shutdown, simulator is already shutdown", error.code];
        [future resolveWithResult:NSNull.null];
      } else if (error) {
        [future resolveWithError:error];
      } else {
        [future resolveWithResult:NSNull.null];
      }
    }];
  return [future
    onQueue:simulator.workQueue fmap:^(id _){
      return [simulator resolveState:FBiOSTargetStateShutdown];
    }];
}

+ (FBFuture<NSNull *> *)transitionCreatingToShutdown:(FBSimulator *)simulator
{
  return [[[simulator
    resolveState:FBiOSTargetStateShutdown]
    timeout:FBControlCoreGlobalConfiguration.regularTimeout waitingFor:@"Simulator to resolve state %@", FBiOSTargetStateStringShutdown]
    onQueue:simulator.workQueue chain:^FBFuture<NSNull *> *(FBFuture *future) {
      if (future.result) {
        return FBFuture.empty;
      }
      return [FBSimulatorShutdownStrategy eraseSimulator:simulator];
    }];
}

+ (FBFuture<NSNull *> *)eraseSimulator:(FBSimulator *)simulator
{
  FBMutableFuture<NSNull *> *future = FBMutableFuture.future;
  id<FBControlCoreLogger> logger = simulator.logger;

  [logger.debug logFormat:@"Erasing Simulator %@", simulator.udid];
  [simulator.device
    eraseContentsAndSettingsAsyncWithCompletionQueue:simulator.asyncQueue completionHandler:^(NSError *error) {
      if (error) {
        [future resolveWithError:error];
      } else {
        [future resolveWithResult:NSNull.null];
      }
    }];

  return [future
    onQueue:simulator.workQueue fmap:^(id _) {
      return [[simulator
        resolveState:FBiOSTargetStateShutdown]
        timeout:FBControlCoreGlobalConfiguration.regularTimeout waitingFor:@"Timed out waiting for Simulator to transition from Creating -> Shutdown"];
    }];
}

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorShutdownStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"

@interface FBSimulatorShutdownStrategy ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorShutdownStrategy

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

- (BOOL)shutdownWithError:(NSError **)error
{
  FBSimulator *simulator = self.simulator;
  id<FBControlCoreLogger> logger = self.simulator.logger;
  [logger.debug logFormat:@"Starting Safe Shutdown of %@", simulator.udid];

  // If the device is in a strange state, we should bail now
  if (simulator.state == FBSimulatorStateUnknown) {
    return [[[[FBSimulatorError
      describe:@"Failed to prepare simulator for usage as it is in an unknown state"]
      inSimulator:simulator]
      logger:logger]
      failBool:error];
  }

  // Calling shutdown when already shutdown should be avoided (if detected).
  if (simulator.state == FBSimulatorStateShutdown) {
    [logger.debug logFormat:@"Shutdown of %@ succeeded as it is already shutdown", simulator.udid];
    return YES;
  }

  // Xcode 7 has a 'Creating' step that we should wait on before confirming the simulator is ready.
  // It is possible to recover from this with a few tricks.
  NSError *innerError = nil;
  if (simulator.state == FBSimulatorStateCreating) {

    [logger.debug logFormat:@"Simulator %@ is Creating, waiting for state to change to Shutdown", simulator.udid];
    if (![simulator waitOnState:FBSimulatorStateShutdown withError:&innerError]) {

      [logger.debug logFormat:@"Simulator %@ is stuck in Creating: erasing now", simulator.udid];
      if (![simulator eraseWithError:&innerError]) {
        return [[[[[FBSimulatorError
          describe:@"Failed trying to prepare simulator for usage by erasing a stuck 'Creating' simulator %@"]
          causedBy:innerError]
          inSimulator:simulator]
          logger:logger]
          failBool:error];
      }

      // If a device has been erased, we should wait for it to actually be shutdown. Ff it can't be, fail
      if (![simulator waitOnState:FBSimulatorStateShutdown withError:&innerError]) {
        return [[[[[FBSimulatorError
          describe:@"Failed trying to wait for a 'Creating' simulator to be shutdown after being erased"]
          causedBy:innerError]
          inSimulator:simulator]
          logger:logger]
          failBool:error];
      }
    }

    [logger.debug logFormat:@"Simulator %@ has transitioned from Creating to Shutdown", simulator.udid];
    return YES;
  }

  // The error code for 'Unable to shutdown device in current state: Shutdown'
  // can be safely ignored since these codes confirm that the simulator is already shutdown.
  [logger.debug logFormat:@"Shutting down Simulator %@", simulator.udid];
  if (![simulator.device shutdownWithError:&innerError] && innerError.code != FBSimulatorShutdownStrategy.errorCodeForShutdownWhenShuttingDown) {
    return [[[[[FBSimulatorError
      describe:@"Simulator could not be shutdown"]
      causedBy:innerError]
      inSimulator:simulator]
      logger:logger]
      failBool:error];
  }

  [logger.debug logFormat:@"Confirming Simulator %@ is shutdown", simulator.udid];
  if (![simulator waitOnState:FBSimulatorStateShutdown withError:&innerError]) {
    return [[[[[FBSimulatorError
      describe:@"Failed to wait for simulator preparation to shutdown device"]
      causedBy:innerError]
      inSimulator:simulator]
      logger:logger]
      failBool:error];
  }
  [logger.debug logFormat:@"Simulator %@ is now shutdown", simulator.udid];
  return YES;
}

+ (NSInteger)errorCodeForShutdownWhenShuttingDown
{
  if (FBControlCoreGlobalConfiguration.isXcode8OrGreater) {
    return 163;
  }
  if (FBControlCoreGlobalConfiguration.isXcode7OrGreater) {
    return 159;
  }
  return 146;
}

@end

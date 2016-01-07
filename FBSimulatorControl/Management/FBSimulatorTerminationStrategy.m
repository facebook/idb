/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorTerminationStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBCollectionDescriptions.h"
#import "FBCoreSimulatorNotifier.h"
#import "FBProcessTerminationStrategy.h"
#import "FBProcessInfo.h"
#import "FBProcessQuery+Simulators.h"
#import "FBProcessQuery.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction.h"
#import "FBSimulatorLogger.h"
#import "FBSimulatorPredicates.h"
#import "FBTaskExecutor+Convenience.h"
#import "FBTaskExecutor.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

@interface FBSimulatorTerminationStrategy ()

@property (nonatomic, copy, readonly) FBSimulatorControlConfiguration *configuration;
@property (nonatomic, strong, readonly) FBProcessQuery *processQuery;
@property (nonatomic, strong, readonly) id<FBSimulatorLogger> logger;
@property (nonatomic, strong, readonly) FBProcessTerminationStrategy *processTerminationStrategy;

@end

@implementation FBSimulatorTerminationStrategy

#pragma mark Initialization

+ (instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration processQuery:(FBProcessQuery *)processQuery logger:(id<FBSimulatorLogger>)logger
{
  BOOL useKill = (configuration.options & FBSimulatorManagementOptionsUseProcessKilling) == FBSimulatorManagementOptionsUseProcessKilling;
  FBProcessTerminationStrategy *processTerminationStrategy = useKill
    ? [FBProcessTerminationStrategy withProcessKilling:processQuery logger:logger]
    : [FBProcessTerminationStrategy withRunningApplicationTermination:processQuery logger:logger];

  return [[self alloc] initWithConfiguration:configuration processQuery:processQuery processTerminationStrategy:processTerminationStrategy logger:logger];

}

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration processQuery:(FBProcessQuery *)processQuery processTerminationStrategy:(FBProcessTerminationStrategy *)processTerminationStrategy logger:(id<FBSimulatorLogger>)logger
{
  NSParameterAssert(processQuery);
  NSParameterAssert(configuration);
  NSParameterAssert(processTerminationStrategy);

  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _processQuery = processQuery;
  _logger = logger;
  _processTerminationStrategy = processTerminationStrategy;

  return self;
}

#pragma mark Public Methods

- (NSArray *)killSimulators:(NSArray *)simulators withError:(NSError **)error
{
  // It looks like there is a bug with El Capitan, where terminating mutliple Applications quickly
  // can result in the dock getting into an inconsistent state displaying icons for terminated Applications.
  // This happens regardless of how the Application was terminated.
  // The process backing the terminated Application is definitely gone, but the Icon isn't.
  // The Application appears in the Force Quit menu, but cannot ever be quit by conventional means.
  // Attempting to shutdown the Mac will result in hanging (probably because it can't terminate the App).
  //
  // The only remedy is to quit 'launchservicesd' followed by 'Dock.app'.
  // This will clear up the stale state that must exist in the Dock/launchservicesd.
  // Waiting after killing of processes by a short period of time is sufficient to mitigate this issue.
  // Since `safeShutdown:withError:` will spin the run loop until CoreSimulator confirms that the device is shutdown,
  // this will give a sufficient amount of time between killing Applications.

  [self.logger.debug logFormat:@"Killing %@", [FBCollectionDescriptions oneLineDescriptionFromArray:simulators atKeyPath:@"shortDescription"]];
  for (FBSimulator *simulator in simulators) {
    FBProcessInfo *simulatorProcess = simulator.launchInfo.simulatorProcess ?: [self.processQuery simulatorApplicationProcessForSimDevice:simulator.device];
    if (!simulatorProcess) {
      [self.logger.debug logFormat:@"Will not kill %@ as it is not launched", simulator.shortDescription];
      continue;
    }
    NSError *innerError = nil;
    if (![self.processTerminationStrategy killProcess:simulatorProcess error:&innerError]) {
      return [[[[[FBSimulatorError
        describeFormat:@"Could not kill simulator process %@", simulatorProcess]
        inSimulator:simulator]
        causedBy:innerError]
        logger:self.logger]
        fail:error];
    }
    if (![self safeShutdownSimulator:simulator withError:&innerError]) {
      return [[[[[FBSimulatorError
        describe:@"Could not shut down simulator after termination"]
        inSimulator:simulator]
        causedBy:innerError]
        logger:self.logger]
        fail:error];
    }
    [self.logger.info logFormat:@"Killed & Shutdown %@", simulator];
  }
  return simulators;
}

- (BOOL)safeShutdownSimulator:(FBSimulator *)simulator withError:(NSError **)error
{
  [self.logger.debug logFormat:@"Starting Safe Shutdown of %@", simulator.udid];

  // If the device is in a strange state, we should bail now
  if (simulator.state == FBSimulatorStateUnknown) {
    return [[[[FBSimulatorError
      describe:@"Failed to prepare simulator for usage as it is in an unknown state"]
      inSimulator:simulator]
      logger:self.logger]
      failBool:error];
  }

  // Calling shutdown when already shutdown should be avoided (if detected).
  if (simulator.state == FBSimulatorStateShutdown) {
    [self.logger.debug logFormat:@"Shutdown of %@ succeeded as it is allready shutdown", simulator.udid];
    return YES;
  }

  // Xcode 7 has a 'Creating' step that we should wait on before confirming the simulator is ready.
  // It is possible to recover from this with a few tricks.
  NSError *innerError = nil;
  if (simulator.state == FBSimulatorStateCreating) {

    [self.logger.debug logFormat:@"Simulator %@ is Creating, waiting for state to change to Shutdown", simulator.udid];
    if (![simulator waitOnState:FBSimulatorStateShutdown withError:&innerError]) {

      [self.logger.debug logFormat:@"Simulator %@ is stuck in Creating: erasing now", simulator.udid];
      if (![simulator eraseWithError:&innerError]) {
        return [[[[[FBSimulatorError
          describe:@"Failed trying to prepare simulator for usage by erasing a stuck 'Creating' simulator %@"]
          causedBy:innerError]
          inSimulator:simulator]
          logger:self.logger]
          failBool:error];
      }

      // If a device has been erased, we should wait for it to actually be shutdown. Ff it can't be, fail
      if (![simulator waitOnState:FBSimulatorStateShutdown withError:&innerError]) {
        return [[[[[FBSimulatorError
          describe:@"Failed trying to wait for a 'Creating' simulator to be shutdown after being erased"]
          causedBy:innerError]
          inSimulator:simulator]
          logger:self.logger]
          failBool:error];
      }
    }

    [self.logger.debug logFormat:@"Simulator %@ has transitioned from Creating to Shutdown", simulator.udid];
    return YES;
  }

  // Code 159 (Xcode 7) or 146 (Xcode 6) is 'Unable to shutdown device in current state: Shutdown'
  // We can safely ignore these codes and then confirm that the simulator is truly shutdown.
  [self.logger.debug logFormat:@"Shutting down Simulator %@", simulator.udid];
  if (![simulator.device shutdownWithError:&innerError] && innerError.code != 159 && innerError.code != 146) {
    return [[[[[FBSimulatorError
      describe:@"Simulator could not be shutdown"]
      causedBy:innerError]
      inSimulator:simulator]
      logger:self.logger]
      failBool:error];
  }


  [self.logger.debug logFormat:@"Confirming Simulator %@ is shutdown", simulator.udid];
  if (![simulator waitOnState:FBSimulatorStateShutdown withError:&innerError]) {
    return [[[[[FBSimulatorError
      describe:@"Failed to wait for simulator preparation to shutdown device"]
      causedBy:innerError]
      inSimulator:simulator]
      logger:self.logger]
      failBool:error];
  }
  [self.logger.debug logFormat:@"Simulator %@ is now shutdown", simulator.udid];
  return YES;
}

- (NSArray *)ensureConsistencyForSimulators:(NSArray *)simulators withError:(NSError **)error
{
  NSPredicate *predicate = [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *simulator, NSDictionary *_) {
    return simulator.launchInfo == nil && simulator.state != FBSimulatorStateShutdown;
  }];
  simulators = [simulators filteredArrayUsingPredicate:predicate];

  for (FBSimulator *simulator in simulators) {
    NSError *innerError = nil;
    if (![self safeShutdownSimulator:simulator withError:&innerError]) {
      return [[[[FBSimulatorError
        describe:@"Failed to ensure consistency by shutting down process-less simulators"]
        inSimulator:simulator]
        logger:self.logger]
        fail:error];
    }
  }
  return simulators;
}

- (BOOL)killSpuriousSimulatorsWithError:(NSError **)error
{
  NSPredicate *predicate = [NSCompoundPredicate notPredicateWithSubpredicate:
    [NSCompoundPredicate andPredicateWithSubpredicates:@[
      [FBProcessQuery simulatorsProcessesLaunchedUnderConfiguration:self.configuration],
      [FBProcessQuery simulatorProcessesLaunchedBySimulatorControl]
    ]
  ]];

  NSError *innerError = nil;
  if (![self killSimulatorProcessesMatchingPredicate:predicate error:&innerError]) {
    return [[[[FBSimulatorError
      describe:@"Could not kill spurious simulators"]
      causedBy:innerError]
      logger:self.logger]
      failBool:error];
  }

  return YES;
}

- (BOOL)killSpuriousCoreSimulatorServicesWithError:(NSError **)error
{
  NSPredicate *predicate = [NSCompoundPredicate notPredicateWithSubpredicate:
    [FBProcessQuery coreSimulatorProcessesForCurrentXcode]
  ];
  NSArray *processes = [[self.processQuery coreSimulatorServiceProcesses] filteredArrayUsingPredicate:predicate];

  return [self killProcesses:processes error:error];
}

#pragma mark Private

- (BOOL)killProcesses:(NSArray *)processes error:(NSError **)error
{
  for (FBProcessInfo *process in processes) {
    NSParameterAssert(process.processIdentifier > 1);
    if (![self.processTerminationStrategy killProcess:process error:error]) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)killSimulatorProcessesMatchingPredicate:(NSPredicate *)predicate error:(NSError **)error
{
  NSArray *processes = [self.processQuery.simulatorProcesses filteredArrayUsingPredicate:predicate];
  for (FBProcessInfo *process in processes) {
    NSParameterAssert(process.processIdentifier > 1);
    if (![self.processTerminationStrategy killProcess:process error:error]) {
      return NO;
    }
    // See comment in `killSimulators:withError:`
    sleep(1);
  }
  return YES;
}

@end

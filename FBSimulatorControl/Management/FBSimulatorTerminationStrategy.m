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
#import "FBProcessInfo.h"
#import "FBProcessQuery+Simulators.h"
#import "FBProcessQuery.h"
#import "FBProcessTerminationStrategy.h"
#import "FBSimDeviceWrapper.h"
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
    ? [FBProcessTerminationStrategy withProcessKilling:processQuery signo:SIGKILL logger:logger]
    : [FBProcessTerminationStrategy withRunningApplicationTermination:processQuery signo:SIGKILL logger:logger];

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
  // It looks like there is a bug with El Capitan, where terminating multiple Applications quickly
  // can result in the dock getting into an inconsistent state displaying icons for terminated Applications.
  //
  // This happens regardless of how the Application was terminated.
  // The process backing the terminated Application is definitely gone, but the dock icon isn't.
  // The Application appears in the Force Quit menu, but cannot ever be quit by conventional means.
  // Attempting to shutdown the Mac will result in hanging (probably because it can't terminate the App).
  //
  // The only remedy is to quit 'launchservicesd' followed by 'Dock.app'.
  // This will clear up the stale state that must exist in the Dock/launchservicesd.
  // Waiting after killing of processes by a short period of time is sufficient to mitigate this issue.
  // Since `-[FBSimDeviceWrapper shutdownWithError:]` will spin the run loop until CoreSimulator confirms that the device is shutdown,
  // this will give a sufficient amount of time between killing Applications.

  [self.logger.debug logFormat:@"Killing %@", [FBCollectionDescriptions oneLineDescriptionFromArray:simulators atKeyPath:@"shortDescription"]];
  for (FBSimulator *simulator in simulators) {
    FBProcessInfo *simulatorProcess = simulator.containerApplication ?: [self.processQuery simulatorApplicationProcessForSimDevice:simulator.device];
    NSError *innerError = nil;

    // Kill the Simulator.app Process first, see documentation in `-[FBSimDeviceWrapper shutdownWithError:]`.
    // This prevents 'Zombie' Simulator.app from existing.
    if (simulatorProcess) {
      [self.logger.debug logFormat:@"Simulator %@ has a Simulator.app Process %@, terminating it now", simulator.shortDescription, simulatorProcess];
      if (![self.processTerminationStrategy killProcess:simulatorProcess error:&innerError]) {
        return [[[[[FBSimulatorError
          describeFormat:@"Could not kill simulator process %@", simulatorProcess]
          inSimulator:simulator]
          causedBy:innerError]
          logger:self.logger]
          fail:error];
      }
    } else {
      [self.logger.debug logFormat:@"Simulator %@ does not have a running Simulator.app Process", simulator.shortDescription];
    }

    // Shutdown will:
    // 1) Wait for a Simulator launched via Simulator.app to be in a consistent 'Shutdown' state.
    // 2) Shutdown a SimDevice that has been launched directly via. `-[SimDevice bootWithOptions:error]`.
    if (![simulator.simDeviceWrapper shutdownWithError:&innerError]) {
      return [[[[[FBSimulatorError
        describe:@"Could not shut down simulator after termination"]
        inSimulator:simulator]
        causedBy:innerError]
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

#pragma mark Private

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

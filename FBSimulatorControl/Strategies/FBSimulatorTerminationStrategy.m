/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorTerminationStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

#import <FBControlCore/FBControlCoreLogger.h>

#import <XCTestBootstrap/FBTestManager.h>

#import "FBCoreSimulatorNotifier.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorPredicates.h"
#import "FBSimulatorShutdownStrategy.h"
#import "FBSimulatorProcessFetcher.h"
#import "FBSimulatorSet.h"

@interface FBSimulatorTerminationStrategy ()

@property (nonatomic, weak, readonly) FBSimulatorSet *set;
@property (nonatomic, copy, readonly) FBSimulatorControlConfiguration *configuration;
@property (nonatomic, strong, readonly) FBSimulatorProcessFetcher *processFetcher;
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) FBProcessTerminationStrategy *processTerminationStrategy;

@end

@implementation FBSimulatorTerminationStrategy

#pragma mark Initialization

+ (instancetype)strategyForSet:(FBSimulatorSet *)set
{
  FBProcessTerminationStrategy *processTerminationStrategy = [FBProcessTerminationStrategy strategyWithProcessFetcher:set.processFetcher.processFetcher workQueue:dispatch_get_main_queue() logger:set.logger];
  return [[self alloc] initWithSet:set configuration:set.configuration processFetcher:set.processFetcher processTerminationStrategy:processTerminationStrategy logger:set.logger];
}

- (instancetype)initWithSet:(FBSimulatorSet *)set configuration:(FBSimulatorControlConfiguration *)configuration processFetcher:(FBSimulatorProcessFetcher *)processFetcher processTerminationStrategy:(FBProcessTerminationStrategy *)processTerminationStrategy logger:(id<FBControlCoreLogger>)logger
{
  NSParameterAssert(processFetcher);
  NSParameterAssert(configuration);
  NSParameterAssert(processTerminationStrategy);

  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;
  _configuration = configuration;
  _processFetcher = processFetcher;
  _logger = logger;
  _processTerminationStrategy = processTerminationStrategy;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSArray<FBSimulator *> *> *)killSimulators:(NSArray<FBSimulator *> *)simulators
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

  [self.logger.debug logFormat:@"Killing %@", [FBCollectionInformation oneLineDescriptionFromArray:simulators atKeyPath:@"shortDescription"]];
  NSMutableArray<FBFuture<FBSimulator *> *> *futures = [NSMutableArray array];
  for (FBSimulator *simulator in simulators) {
    [futures addObject:[self killSimulator:simulator]];
  }
  return [FBFuture futureWithFutures:futures];
}

- (FBFuture<NSNull *> *)killSpuriousSimulators
{
  NSPredicate *predicate = [NSCompoundPredicate notPredicateWithSubpredicate:
    [NSCompoundPredicate andPredicateWithSubpredicates:@[
      [FBSimulatorProcessFetcher simulatorsProcessesLaunchedUnderConfiguration:self.configuration],
      [FBSimulatorProcessFetcher simulatorApplicationProcessesLaunchedBySimulatorControl]
    ]
  ]];

  return [[self
    killSimulatorProcessesMatchingPredicate:predicate]
    rephraseFailure:@"Could not kill spurious simulators"];
}

#pragma mark Private

- (FBFuture<FBSimulator *> *)killSimulator:(FBSimulator *)simulator
{
  // Before doing anything, get a reference to the current launchd process.
  FBProcessInfo *launchdProcess = simulator.launchdProcess ?: [self.processFetcher launchdProcessForSimDevice:simulator.device];

  // The Simulator Connection for this process should be tidied up first.
  FBFuture<NSNull *> *disconnectFuture = [simulator disconnectWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout logger:self.logger];

  // Kill the Simulator.app Process first, see documentation in `-[FBSimDeviceWrapper shutdownWithError:]`.
  // This prevents 'Zombie' Simulator.app from existing.
  FBProcessInfo *simulatorProcess = simulator.containerApplication ?: [self.processFetcher simulatorApplicationProcessForSimDevice:simulator.device];
  FBFuture<NSNull *> *simulatorAppProcessKillFuture = nil;
  if (simulatorProcess) {
    [self.logger.debug logFormat:@"Simulator %@ has a Simulator.app Process %@, terminating it now", simulator.shortDescription, simulatorProcess];
    simulatorAppProcessKillFuture = [[self.processTerminationStrategy
      killProcess:simulatorProcess]
      onQueue:simulator.workQueue map:^(id _) {
        [simulator.eventSink containerApplicationDidTerminate:simulatorProcess expected:YES];
        return NSNull.null;
      }];
  } else {
    [self.logger.debug logFormat:@"Simulator %@ does not have a running Simulator.app Process", simulator.shortDescription];
    simulatorAppProcessKillFuture = FBFuture.empty;
  }

  // Shutdown will:
  // 1) Wait for the Connection to the Simulator to Disconnect.
  // 2) Wait for a Simulator launched via Simulator.app to be in a consistent 'Shutdown' state.
  // 3) Shutdown a SimDevice that has been launched directly via. `-[SimDevice bootWithOptions:error]`.
  return [[[disconnectFuture
    chainReplace:simulatorAppProcessKillFuture]
    onQueue:simulator.workQueue fmap:^(id _) {
      return [[FBSimulatorShutdownStrategy
        strategyWithSimulator:simulator]
        shutdown];
    }]
    onQueue:simulator.workQueue map:^(id _) {
      if (launchdProcess) {
        [simulator.eventSink simulatorDidTerminate:launchdProcess expected:YES];
      }
      return simulator;
    }];
}

- (FBFuture<NSNull *> *)killSimulatorProcessesMatchingPredicate:(NSPredicate *)predicate
{
  NSArray<FBProcessInfo *> *processes = [self.processFetcher.simulatorApplicationProcesses filteredArrayUsingPredicate:predicate];
  NSMutableArray<FBFuture<NSNull *> *> *futures = [NSMutableArray array];

  for (FBProcessInfo *process in processes) {
    NSParameterAssert(process.processIdentifier > 1);
    FBFuture<NSNull *> *future = [[self.processTerminationStrategy
      killProcess:process]
      delay:1];
    [futures addObject:future];
  }
  return [FBFuture futureWithFutures:futures];
}

@end

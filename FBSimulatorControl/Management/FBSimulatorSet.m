/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorSet.h"
#import "FBSimulatorSet+Private.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>
#import <CoreSimulator/SimServiceContext.h>

#import <FBControlCore/FBControlCore.h>

#import <objc/runtime.h>

#import "FBCoreSimulatorNotifier.h"
#import "FBCoreSimulatorTerminationStrategy.h"
#import "FBSimulatorContainerApplicationLifecycleStrategy.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorControlFrameworkLoader.h"
#import "FBSimulatorDeletionStrategy.h"
#import "FBSimulatorEraseStrategy.h"
#import "FBSimulatorInflationStrategy.h"
#import "FBSimulatorShutdownStrategy.h"
#import "FBSimulatorTerminationStrategy.h"
#import "FBSimulatorNotificationUpdateStrategy.h"

@implementation FBSimulatorSet

@synthesize allSimulators = _allSimulators;
@synthesize delegate = _delegate;

#pragma mark Initializers

+ (void)initialize
{
  [FBSimulatorControlFrameworkLoader.essentialFrameworks loadPrivateFrameworksOrAbort];
}

+ (instancetype)setWithConfiguration:(FBSimulatorControlConfiguration *)configuration deviceSet:(SimDeviceSet *)deviceSet delegate:(id<FBiOSTargetSetDelegate>)delegate logger:(id<FBControlCoreLogger>)logger reporter:(id<FBEventReporter>)reporter error:(NSError **)error
{
  NSError *innerError = nil;
  FBSimulatorSet *set = [[FBSimulatorSet alloc] initWithConfiguration:configuration deviceSet:deviceSet delegate:delegate logger:logger reporter:reporter];
  if (![set performSetPreconditionsWithConfiguration:configuration Error:&innerError]) {
    return [[[[FBSimulatorError
      describe:@"Failed meet simulator set preconditions"]
      causedBy:innerError]
      logger:logger]
      fail:error];
  }
  return set;
}

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration deviceSet:(SimDeviceSet *)deviceSet delegate:(id<FBiOSTargetSetDelegate>)delegate logger:(id<FBControlCoreLogger>)logger reporter:(id<FBEventReporter>)reporter
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _deviceSet = deviceSet;
  _delegate = delegate;
  _logger = logger;
  _reporter = reporter;
  _workQueue = dispatch_get_main_queue();
  _asyncQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

  _allSimulators = @[];
  _processFetcher = [FBSimulatorProcessFetcher fetcherWithProcessFetcher:[FBProcessFetcher new]];
  _inflationStrategy = [FBSimulatorInflationStrategy strategyForSet:self];
  _containerApplicationStrategy = [FBSimulatorContainerApplicationLifecycleStrategy strategyForSet:self];
  _notificationUpdateStrategy = [FBSimulatorNotificationUpdateStrategy strategyWithSet:self];

  return self;
}

- (BOOL)performSetPreconditionsWithConfiguration:(FBSimulatorControlConfiguration *)configuration Error:(NSError **)error
{
  NSError *innerError = nil;
  BOOL killSpuriousCoreSimulatorServices = (configuration.options & FBSimulatorManagementOptionsKillSpuriousCoreSimulatorServices) == FBSimulatorManagementOptionsKillSpuriousCoreSimulatorServices;
  if (killSpuriousCoreSimulatorServices) {
    if (![self.coreSimulatorTerminationStrategy killSpuriousCoreSimulatorServicesWithError:&innerError]) {
      return [[[[FBSimulatorError
        describe:@"Failed to kill spurious CoreSimulatorServices"]
        causedBy:innerError]
        logger:self.logger]
        failBool:error];
    }
  }

  BOOL deleteOnStart = (configuration.options & FBSimulatorManagementOptionsDeleteAllOnFirstStart) == FBSimulatorManagementOptionsDeleteAllOnFirstStart;
  if (deleteOnStart) {
    if (![[self deleteAll] await:&innerError]) {
      return [[[[FBSimulatorError
        describe:@"Failed to delete all simulators"]
        causedBy:innerError]
        logger:self.logger]
        failBool:error];
    }
  }

  // Deletion requires killing, so don't duplicate killing.
  BOOL killOnStart = (configuration.options & FBSimulatorManagementOptionsKillAllOnFirstStart) == FBSimulatorManagementOptionsKillAllOnFirstStart;
  if (killOnStart && !deleteOnStart) {
    if (![[self killAll] await:&innerError]) {
      return [[[[FBSimulatorError
        describe:@"Failed to kill all simulators"]
        causedBy:innerError]
        logger:self.logger]
        failBool:error];
    }
  }

  BOOL killSpuriousSimulators = (configuration.options & FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart) == FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart;
  if (killSpuriousSimulators && !deleteOnStart) {
    BOOL failOnSpuriousKillFail = (configuration.options & FBSimulatorManagementOptionsIgnoreSpuriousKillFail) != FBSimulatorManagementOptionsIgnoreSpuriousKillFail;
    if (![self  killSpuriousSimulatorsWithError:&innerError] && failOnSpuriousKillFail) {
      return [[[[FBSimulatorError
      describe:@"Failed to kill spurious simulators"]
      causedBy:innerError]
      logger:self.logger]
      failBool:error];
    }
  }

  [self.logger.debug logFormat:@"Completed Pool Preconditons"];
  return YES;
}

#pragma mark Querying

- (NSArray<FBSimulator *> *)query:(FBiOSTargetQuery *)query
{
  if ([query excludesAll:FBiOSTargetTypeSimulator]) {
    return @[];
  }
  return (NSArray<FBSimulator *> *) [query filter:self.allSimulators];
}

#pragma mark Creation

- (FBFuture<FBSimulator *> *)createSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration
{
  FBDeviceModel model = configuration.device.model;

  // See if we meet the runtime requirements to create a Simulator with the given configuration.
  NSError *innerError = nil;
  SimDeviceType *deviceType = [configuration obtainDeviceTypeWithError:&innerError];
  if (!deviceType) {
    return [[[[FBSimulatorError
      describeFormat:@"Could not obtain a DeviceType for Configuration %@", configuration]
      causedBy:innerError]
      logger:self.logger]
      failFuture];
  }
  SimRuntime *runtime = [configuration obtainRuntimeWithError:&innerError];
  if (!runtime) {
    return [[[[FBSimulatorError
      describeFormat:@"Could not obtain a SimRuntime for Configuration %@", configuration]
      causedBy:innerError]
      logger:self.logger]
      failFuture];
  }

  // First, create the device.
  [self.logger.debug logFormat:@"Creating device with Type %@ Runtime %@", deviceType, runtime];
  return [[[FBSimulatorSet
    onDeviceSet:self.deviceSet createDeviceWithType:deviceType runtime:runtime name:model queue:self.asyncQueue]
    onQueue:self.workQueue fmap:^(SimDevice *device) {
      return [self fetchNewlyMadeSimulator:device];
    }]
    onQueue:self.workQueue fmap:^(FBSimulator *simulator) {
      simulator.configuration = configuration;
      [self.logger.debug logFormat:@"Created Simulator %@ for configuration %@", simulator.udid, configuration];

      // This step ensures that the Simulator is in a known-shutdown state after creation.
      // This prevents racing with any 'booting' interaction that occurs immediately after allocation.
      return [[[[FBSimulatorShutdownStrategy
        strategyWithSimulator:simulator]
        shutdown]
        rephraseFailure:@"Could not get newly-created simulator into a shutdown state"]
        mapReplace:simulator];
    }];
}

- (FBFuture<FBSimulator *> *)cloneSimulator:(FBSimulator *)simulator toDeviceSet:(FBSimulatorSet *)destinationSet
{
  NSParameterAssert(simulator.set == self);
  return [[FBSimulatorSet
    onDeviceSet:self.deviceSet cloneDevice:simulator.device toDeviceSet:destinationSet.deviceSet queue:self.asyncQueue]
    onQueue:self.workQueue fmap:^(SimDevice *device) {
      return [destinationSet fetchNewlyMadeSimulator:device];
    }];
}

- (NSArray<FBSimulatorConfiguration *> *)configurationsForAbsentDefaultSimulators
{
  NSSet<FBSimulatorConfiguration *> *existingConfigurations = [NSSet setWithArray:[self.allSimulators valueForKey:@"configuration"]];
  NSMutableSet<FBSimulatorConfiguration *> *absentConfigurations = [NSMutableSet setWithArray:[FBSimulatorConfiguration allAvailableDefaultConfigurationsWithLogger:self.logger]];
  [absentConfigurations minusSet:existingConfigurations];
  return [absentConfigurations allObjects];
}

#pragma mark Destructive Methods

- (FBFuture<FBSimulator *> *)killSimulator:(FBSimulator *)simulator
{
  NSParameterAssert(simulator);
  return [[self.simulatorTerminationStrategy
    killSimulators:@[simulator]]
    onQueue:self.workQueue map:^(NSArray<FBSimulator *> *result) {
      return [result firstObject];
    }];
}

- (FBFuture<FBSimulator *> *)eraseSimulator:(FBSimulator *)simulator
{
  NSParameterAssert(simulator);
  return [[self.eraseStrategy
    eraseSimulators:@[simulator]]
    onQueue:self.workQueue map:^(NSArray<FBSimulator *> *result) {
      return [result firstObject];
    }];
}

- (FBFuture<NSString *> *)deleteSimulator:(FBSimulator *)simulator
{
  NSParameterAssert(simulator);
  return [[self.deletionStrategy
    deleteSimulators:@[simulator]]
    onQueue:self.workQueue map:^(NSArray<NSString *> *result) {
      return [result firstObject];
    }];
}

- (FBFuture<NSArray<FBSimulator *> *> *)killAll:(NSArray<FBSimulator *> *)simulators
{
  NSParameterAssert(simulators);
  return [self.simulatorTerminationStrategy killSimulators:simulators];
}

- (FBFuture<NSArray<FBSimulator *> *> *)eraseAll:(NSArray<FBSimulator *> *)simulators
{
  NSParameterAssert(simulators);
  return [self.eraseStrategy eraseSimulators:simulators];
}

- (FBFuture<NSArray<NSString *> *> *)deleteAll:(NSArray<FBSimulator *> *)simulators;
{
  NSParameterAssert(simulators);
  return [self.deletionStrategy deleteSimulators:simulators];
}

- (FBFuture<NSArray<FBSimulator *> *> *)killAll
{
  return [self.simulatorTerminationStrategy killSimulators:self.allSimulators];
}

- (FBFuture<NSArray<FBSimulator *> *> *)eraseAll
{
  return [self.eraseStrategy eraseSimulators:self.allSimulators];
}

- (FBFuture<NSArray<NSString *> *> *)deleteAll
{
  return [self deleteAll:self.allSimulators];
}

#pragma mark FBDebugDescribeable Protocol

- (NSString *)shortDescription
{
  return [FBCollectionInformation oneLineDescriptionFromArray:[self.allSimulators valueForKey:NSStringFromSelector(@selector(shortDescription))]];
}

- (NSString *)debugDescription
{
  return [FBCollectionInformation oneLineDescriptionFromArray:[self.allSimulators valueForKey:NSStringFromSelector(@selector(debugDescription))]];
}

- (NSString *)description
{
  return [self shortDescription];
}

#pragma mark FBJSONSerializable Protocol

- (id)jsonSerializableRepresentation
{
  return [self.allSimulators valueForKey:NSStringFromSelector(@selector(jsonSerializableRepresentation))];
}

#pragma mark Private Methods

- (BOOL)killSpuriousSimulatorsWithError:(NSError **)error
{
  return [[self.simulatorTerminationStrategy killSpuriousSimulators] await:error] != nil;
}

+ (NSDictionary<NSString *, FBSimulator *> *)keySimulatorsByUDID:(NSArray *)simulators
{
  NSMutableDictionary<NSString *, FBSimulator *> *dictionary = [NSMutableDictionary dictionary];
  for (FBSimulator *simulator in simulators) {
    dictionary[simulator.udid] = simulator;
  }
  return [dictionary copy];
}

- (FBFuture<FBSimulator *> *)fetchNewlyMadeSimulator:(SimDevice *)device
{
  // The SimDevice should now be in the DeviceSet and thus in the collection of Simulators.
  FBSimulator *simulator = [FBSimulatorSet keySimulatorsByUDID:self.allSimulators][device.UDID.UUIDString];
  if (!simulator) {
    return [[[FBSimulatorError
      describeFormat:@"Expected simulator with UDID %@ to be inflated", device.UDID.UUIDString]
      logger:self.logger]
      failFuture];
  }
  return [FBFuture futureWithResult:simulator];
}

#pragma mark Public Properties

- (NSArray<FBSimulator *> *)allSimulators
{
  _allSimulators = [[self.inflationStrategy
    inflateFromDevices:self.deviceSet.availableDevices exitingSimulators:_allSimulators]
    sortedArrayUsingSelector:@selector(compare:)];
  return _allSimulators;
}

- (NSArray<FBSimulator *> *)launchedSimulators
{
  return [self.allSimulators filteredArrayUsingPredicate:FBSimulatorPredicates.launched];
}

#pragma mark FBiOSTargetSet Implementation

- (NSArray<id<FBiOSTarget>> *)allTargetInfos
{
  return self.allSimulators;
}

#pragma mark Private Properties

- (FBSimulatorTerminationStrategy *)simulatorTerminationStrategy
{
  return [FBSimulatorTerminationStrategy strategyForSet:self];
}

- (FBCoreSimulatorTerminationStrategy *)coreSimulatorTerminationStrategy
{
  return [FBCoreSimulatorTerminationStrategy strategyWithProcessFetcher:self.processFetcher workQueue:self.workQueue logger:self.logger];
}

- (FBSimulatorEraseStrategy *)eraseStrategy
{
  return [FBSimulatorEraseStrategy strategyForSet:self];
}

- (FBSimulatorDeletionStrategy *)deletionStrategy
{
  return [FBSimulatorDeletionStrategy strategyForSet:self];
}

+ (FBFuture<SimDevice *> *)onDeviceSet:(SimDeviceSet *)deviceSet createDeviceWithType:(SimDeviceType *)deviceType runtime:(SimRuntime *)runtime name:(NSString *)name queue:(dispatch_queue_t)queue
{
  FBMutableFuture<SimDevice *> *future = FBMutableFuture.future;
  [deviceSet createDeviceAsyncWithType:deviceType runtime:runtime name:name completionQueue:queue completionHandler:^(NSError *error, SimDevice *device) {
    if (device) {
      [future resolveWithResult:device];
    } else {
      [future resolveWithError:error];
    }
  }];
  return future;
}

+ (FBFuture<SimDevice *> *)onDeviceSet:(SimDeviceSet *)deviceSet cloneDevice:(SimDevice *)device toDeviceSet:(SimDeviceSet *)destinationSet queue:(dispatch_queue_t)queue
{
  FBMutableFuture<SimDevice *> *future = FBMutableFuture.future;
  [deviceSet cloneDeviceAsync:device name:device.name toSet:destinationSet completionQueue:queue completionHandler:^(NSError *error, SimDevice *created) {
    if (created) {
      [future resolveWithResult:created];
    } else {
      [future resolveWithError:error];
    }
  }];
  return future;
}

@end

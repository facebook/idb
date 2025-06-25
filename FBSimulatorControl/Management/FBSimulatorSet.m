/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorControlFrameworkLoader.h"
#import "FBSimulatorDeletionStrategy.h"
#import "FBSimulatorEraseStrategy.h"
#import "FBSimulatorInflationStrategy.h"
#import "FBSimulatorNotificationUpdateStrategy.h"
#import "FBSimulatorShutdownStrategy.h"

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
  return [[FBSimulatorSet alloc] initWithConfiguration:configuration deviceSet:deviceSet delegate:delegate logger:logger reporter:reporter];
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
  _workQueue = configuration.workQueue ? configuration.workQueue : dispatch_get_main_queue();
  _asyncQueue = configuration.asyncQueue ? configuration.asyncQueue : dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

  _allSimulators = @[];
  _inflationStrategy = [FBSimulatorInflationStrategy strategyForSet:self];
  _notificationUpdateStrategy = [FBSimulatorNotificationUpdateStrategy strategyWithSet:self];

  return self;
}

#pragma mark Querying

- (id<FBiOSTargetInfo>)targetWithUDID:(NSString *)udid
{
  return [self simulatorWithUDID:udid];
}

- (FBSimulator *)simulatorWithUDID:(NSString *)udid
{
  return [[self.allSimulators filteredArrayUsingPredicate:FBiOSTargetPredicateForUDID(udid)] firstObject];
}

#pragma mark Creation

- (FBFuture<FBSimulator *> *)createSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration
{
  FBDeviceModel model = configuration.device.model;

  // See if we meet the runtime requirements to create a Simulator with the given configuration.
  NSError *innerError = nil;
  SimDeviceType *deviceType = [configuration obtainDeviceTypeWithError:&innerError];
  if (!deviceType) {
    return [[[FBSimulatorError
      describeFormat:@"Could not obtain a DeviceType for Configuration %@", configuration]
      causedBy:innerError]
      failFuture];
  }
  SimRuntime *runtime = [configuration obtainRuntimeWithError:&innerError];
  if (!runtime) {
    return [[[FBSimulatorError
      describeFormat:@"Could not obtain a SimRuntime for Configuration %@", configuration]
      causedBy:innerError]
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
      return [[[FBSimulatorShutdownStrategy
        shutdown:simulator]
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

- (FBFuture<NSNull *> *)shutdown:(FBSimulator *)simulator
{
  NSParameterAssert(simulator);
  return [FBSimulatorShutdownStrategy shutdown:simulator];
}

- (FBFuture<NSNull *> *)erase:(FBSimulator *)simulator
{
  NSParameterAssert(simulator);
  return [FBSimulatorEraseStrategy erase:simulator];
}

- (FBFuture<NSNull *> *)delete:(FBSimulator *)simulator
{
  NSParameterAssert(simulator);
  return [FBSimulatorDeletionStrategy delete:simulator];
}

- (FBFuture<NSNull *> *)shutdownAll:(NSArray<FBSimulator *> *)simulators
{
  NSParameterAssert(simulators);
  return [FBSimulatorShutdownStrategy shutdownAll:simulators];
}

- (FBFuture<NSNull *> *)deleteAll:(NSArray<FBSimulator *> *)simulators;
{
  NSParameterAssert(simulators);
  return [FBSimulatorDeletionStrategy deleteAll:simulators];
}

- (FBFuture<NSNull *> *)shutdownAll
{
  NSArray<FBSimulator *> *simulators = self.allSimulators;
  return [FBSimulatorShutdownStrategy shutdownAll:simulators];
}

- (FBFuture<NSNull *> *)deleteAll
{
  return [self deleteAll:self.allSimulators];
}

#pragma mark NSObject

- (NSString *)description
{
  return [FBCollectionInformation oneLineDescriptionFromArray:self.allSimulators];
}

#pragma mark Private Methods

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
    return [[FBSimulatorError
      describeFormat:@"Expected simulator with UDID %@ to be inflated", device.UDID.UUIDString]
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

#pragma mark FBiOSTargetSet Implementation

- (NSArray<id<FBiOSTarget>> *)allTargetInfos
{
  return self.allSimulators;
}

#pragma mark Private Properties

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

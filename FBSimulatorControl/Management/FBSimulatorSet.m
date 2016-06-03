/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSet.h"
#import "FBSimulatorSet+Private.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

#import <FBControlCore/FBControlCore.h>

#import "FBCoreSimulatorTerminationStrategy.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorEraseStrategy.h"
#import "FBSimulatorDeletionStrategy.h"
#import "FBSimulatorTerminationStrategy.h"

@implementation FBSimulatorSet

#pragma mark Initializers

+ (void)initialize
{
  [FBSimulatorControl loadPrivateFrameworksOrAbort];
}

+ (instancetype)setWithConfiguration:(FBSimulatorControlConfiguration *)configuration control:(FBSimulatorControl *)control logger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSError *innerError = nil;
  SimDeviceSet *deviceSet = [self createDeviceSetWithConfiguration:configuration error:&innerError];
  if (!deviceSet) {
    return [[[FBSimulatorError describe:@"Failed to create device set"] causedBy:innerError] fail:error];
  }

  FBSimulatorSet *set = [[FBSimulatorSet alloc] initWithConfiguration:configuration deviceSet:deviceSet control:control logger:logger];
  if (![set performSetPreconditionsWithConfiguration:configuration Error:&innerError]) {
    return [[[FBSimulatorError describe:@"Failed meet simulator set preconditions"] causedBy:innerError] fail:error];
  }
  return set;
}

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration deviceSet:(SimDeviceSet *)deviceSet control:(FBSimulatorControl *)control logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logger = logger;
  _deviceSet = deviceSet;
  _control = control;
  _configuration = configuration;

  _inflatedSimulators = [NSMutableDictionary dictionary];
  _processFetcher = [FBProcessFetcher new];

  return self;
}

+ (SimDeviceSet *)createDeviceSetWithConfiguration:(FBSimulatorControlConfiguration *)configuration error:(NSError **)error
{
  NSString *deviceSetPath = configuration.deviceSetPath;
  NSError *innerError = nil;
  if (deviceSetPath != nil) {
    if (![NSFileManager.defaultManager createDirectoryAtPath:deviceSetPath withIntermediateDirectories:YES attributes:nil error:&innerError]) {
      return [[[FBSimulatorError describeFormat:@"Failed to create custom SimDeviceSet directory at %@", deviceSetPath] causedBy:innerError] fail:error];
    }
  }

  return deviceSetPath
    ? [NSClassFromString(@"SimDeviceSet") setForSetPath:configuration.deviceSetPath]
    : [NSClassFromString(@"SimDeviceSet") defaultSet];
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
    if (![self deleteAllWithError:&innerError]) {
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
    if (![self killAllWithError:&innerError]) {
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
    if (![self.simulatorTerminationStrategy killSpuriousSimulatorsWithError:&innerError] && failOnSpuriousKillFail) {
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

#pragma mark - Public Methods

#pragma mark Querying

- (NSArray<FBSimulator *> *)query:(FBiOSTargetQuery *)query
{
  NSMutableArray<NSPredicate *> *predicates = [NSMutableArray array];
  if (query.udids.count > 0) {
    [predicates addObject:[FBSimulatorPredicates udids:query.udids.allObjects]];
  }
  if (query.states.count > 0) {
    [predicates addObject:[FBSimulatorPredicates states:query.states]];
  }
  if (query.osVersions.count > 0) {
    [predicates addObject:[FBSimulatorPredicates osVersions:query.osVersions.allObjects]];
  }
  if (query.devices.count > 0) {
    [predicates addObject:[FBSimulatorPredicates devices:query.devices.allObjects]];
  }

  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:predicates];
  NSArray<FBSimulator *> *simulators = [self.allSimulators filteredArrayUsingPredicate:predicate];
  if (query.range.location == NSNotFound && query.range.length == 0) {
    return simulators;
  }
  NSRange range = NSIntersectionRange(query.range, NSMakeRange(0, simulators.count - 1));
  return [simulators subarrayWithRange:range];
}

#pragma mark Creation

- (nullable FBSimulator *)createSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration error:(NSError **)error
{
  NSString *targetName = configuration.deviceName;

  // See if we meet the runtime requirements to create a Simulator with the given configuration.
  NSError *innerError = nil;
  SimDeviceType *deviceType = [configuration obtainDeviceTypeWithError:&innerError];
  if (!deviceType) {
    return [[[[FBSimulatorError
      describeFormat:@"Could not obtain a DeviceType for Configuration %@", configuration]
      causedBy:innerError]
      logger:self.logger]
      fail:error];
  }
  SimRuntime *runtime = [configuration obtainRuntimeWithError:&innerError];
  if (!runtime) {
    return [[[[FBSimulatorError
      describeFormat:@"Could not obtain a SimRuntime for Configuration %@", configuration]
      causedBy:innerError]
      logger:self.logger]
      fail:error];
  }

  // First, create the device.
  [self.logger.debug logFormat:@"Creating device with Type %@ Runtime %@", deviceType, runtime];
  SimDevice *device = [self.deviceSet createDeviceWithType:deviceType runtime:runtime name:targetName error:&innerError];
  if (!device) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to create a simulator with the name %@, runtime %@, type %@", targetName, runtime, deviceType]
      causedBy:innerError]
      logger:self.logger]
      fail:error];
  }

  // The SimDevice should now be in the DeviceSet and thus in the collection of Simulators.
  FBSimulator *simulator = [FBSimulatorSet keySimulatorsByUDID:self.allSimulators][device.UDID.UUIDString];
  if (!simulator) {
    return [[[FBSimulatorError
      describeFormat:@"Expected simulator with UDID %@ to be inflated", device.UDID.UUIDString]
      logger:self.logger]
      fail:error];
  }
  simulator.configuration = configuration;
  [self.logger.debug logFormat:@"Created Simulator %@ for configuration %@", simulator.udid, configuration];

  // This step ensures that the Simulator is in a known-shutdown state after creation.
  // This prevents racing with any 'booting' interaction that occurs immediately after allocation.
  if (![simulator.simDeviceWrapper shutdownWithError:&innerError]) {
    return [[[[[FBSimulatorError
      describeFormat:@"Could not get newly-created simulator into a shutdown state"]
      inSimulator:simulator]
      causedBy:innerError]
      logger:self.logger]
      fail:error];
  }

  return simulator;
}

#pragma mark Destructive Methods

- (BOOL)killSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  NSParameterAssert(simulator);
  return [self.simulatorTerminationStrategy killSimulators:@[simulator] error:error] != nil;
}

- (BOOL)eraseSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  NSParameterAssert(simulator);
  return [self.eraseStrategy eraseSimulators:@[simulator] error:error] != nil;
}

- (BOOL)deleteSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  NSParameterAssert(simulator);
  return [self.deletionStrategy deleteSimulators:@[simulator] error:error] != nil;
}

- (nullable NSArray<FBSimulator *> *)killAll:(NSArray<FBSimulator *> *)simulators error:(NSError **)error
{
  NSParameterAssert(simulators);
  return [self.simulatorTerminationStrategy killSimulators:simulators error:error];
}

- (nullable NSArray<FBSimulator *> *)eraseAll:(NSArray<FBSimulator *> *)simulators error:(NSError **)error
{
  NSParameterAssert(simulators);
  return [self.eraseStrategy eraseSimulators:simulators error:error];
}

- (nullable NSArray<NSString *> *)deleteAll:(NSArray<FBSimulator *> *)simulators error:(NSError **)error
{
  NSParameterAssert(simulators);
  return [self.deletionStrategy deleteSimulators:simulators error:error];
}

- (nullable NSArray<FBSimulator *> *)killAllWithError:(NSError **)error
{
  return [self.simulatorTerminationStrategy killSimulators:self.allSimulators error:error];
}

- (nullable NSArray<FBSimulator *> *)eraseAllWithError:(NSError **)error
{
  return [self.eraseStrategy eraseSimulators:self.allSimulators error:error];
}

- (nullable NSArray<NSString *> *)deleteAllWithError:(NSError **)error
{
  return [self deleteSimulators:self.allSimulators error:error];
}

#pragma mark FBDebugDescribeable Protocol

- (NSString *)shortDescription
{
  return [self.allSimulators valueForKey:NSStringFromSelector(@selector(shortDescription))];
}

- (NSString *)debugDescription
{
  return [self.allSimulators valueForKey:NSStringFromSelector(@selector(debugDescription))];
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
  return [self.simulatorTerminationStrategy killSpuriousSimulatorsWithError:error];
}

- (nullable NSArray<NSString *> *)deleteSimulators:(NSArray<FBSimulator *> *)simulators error:(NSError **)error
{
  NSError *innerError = nil;
  NSMutableArray *deletedSimulatorNames = [NSMutableArray array];
  for (FBSimulator *simulator in simulators) {
    NSString *simulatorName = simulator.name;
    if (![self deleteSimulator:simulator error:&innerError]) {
      return [FBSimulatorError failWithError:innerError errorOut:error];
    }
    [deletedSimulatorNames addObject:simulatorName];
  }
  return [deletedSimulatorNames copy];
}

+ (NSDictionary<NSString *, FBSimulator *> *)keySimulatorsByUDID:(NSArray *)simulators
{
  NSMutableDictionary<NSString *, FBSimulator *> *dictionary = [NSMutableDictionary dictionary];
  for (FBSimulator *simulator in simulators) {
    dictionary[simulator.udid] = simulator;
  }
  return [dictionary copy];
}

#pragma mark - Properties

#pragma mark Public

- (NSArray<FBSimulator *> *)allSimulators
{
  // Inflate new simulators that have come along since last time this method was called.
  NSArray *simDevices = self.deviceSet.availableDevices;
  for (SimDevice *device in simDevices) {
    NSString *udid = device.UDID.UUIDString;
    if (self.inflatedSimulators[udid]) {
      continue;
    }
    FBSimulator *simulator = [FBSimulator fromSimDevice:device configuration:nil set:self];
    self.inflatedSimulators[udid] = simulator;
  }

  // Cull Simulators that should have gone away.
  NSArray *currentSimulatorUDIDs = [simDevices valueForKeyPath:@"UDID.UUIDString"];
  NSMutableSet *cullSet = [NSMutableSet setWithArray:self.inflatedSimulators.allKeys];
  [cullSet minusSet:[NSSet setWithArray:currentSimulatorUDIDs]];
  [self.inflatedSimulators removeObjectsForKeys:cullSet.allObjects];

  return [self.inflatedSimulators objectsForKeys:currentSimulatorUDIDs notFoundMarker:NSNull.null];
}

- (NSArray<FBSimulator *> *)launchedSimulators
{
  return [self.allSimulators filteredArrayUsingPredicate:FBSimulatorPredicates.launched];
}

#pragma mark Private

- (FBSimulatorTerminationStrategy *)simulatorTerminationStrategy
{
  return [FBSimulatorTerminationStrategy strategyForSet:self];
}

- (FBCoreSimulatorTerminationStrategy *)coreSimulatorTerminationStrategy
{
  return [FBCoreSimulatorTerminationStrategy withProcessFetcher:self.processFetcher logger:self.logger];
}

- (FBSimulatorEraseStrategy *)eraseStrategy
{
  return [FBSimulatorEraseStrategy strategyForSet:self];
}

- (FBSimulatorDeletionStrategy *)deletionStrategy
{
  return [FBSimulatorDeletionStrategy strategyForSet:self];
}

@end

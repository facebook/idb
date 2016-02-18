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

#import "FBCoreSimulatorTerminationStrategy.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorLogger.h"
#import "FBSimulatorTerminationStrategy.h"

@implementation FBSimulatorSet

#pragma mark Initializers

+ (void)initialize
{
  [FBSimulatorControl loadPrivateFrameworksOrAbort];
}

+ (instancetype)setWithConfiguration:(FBSimulatorControlConfiguration *)configuration logger:(id<FBSimulatorLogger>)logger error:(NSError **)error
{
  NSError *innerError = nil;
  SimDeviceSet *deviceSet = [self createDeviceSetWithConfiguration:configuration error:&innerError];
  if (!deviceSet) {
    return [[[FBSimulatorError describe:@"Failed to create device set"] causedBy:innerError] fail:error];
  }

  FBSimulatorSet *set = [[FBSimulatorSet alloc] initWithConfiguration:configuration deviceSet:deviceSet logger:logger];
  if (![set performSetPreconditionsWithConfiguration:configuration Error:&innerError]) {
    return [[[FBSimulatorError describe:@"Failed meet pool preconditions"] causedBy:innerError] fail:error];
  }
  return set;
}

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration deviceSet:(SimDeviceSet *)deviceSet logger:(id<FBSimulatorLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logger = logger;
  _deviceSet = deviceSet;
  _configuration = configuration;

  _inflatedSimulators = [NSMutableDictionary dictionary];
  _processQuery = [FBProcessQuery new];

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

#pragma mark Public Methods

- (FBSimulator *)createSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration error:(NSError **)error
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


- (BOOL)deleteSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  NSParameterAssert(simulator);
  NSParameterAssert(simulator.device.deviceSet != self.deviceSet);

  // Kill the Simulators before deleting them.
  NSError *innerError = nil;
  if (![self.simulatorTerminationStrategy killSimulators:@[simulator] withError:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  // Delete the Device from the Underlying DeviceSet
  NSString *udid = simulator.udid;
  if (![self.deviceSet deleteDevice:simulator.device error:&innerError]) {
    return [[[[[FBSimulatorError
      describeFormat:@"Failed to Delete simulator %@", simulator]
      causedBy:innerError]
      inSimulator:simulator]
      logger:self.logger]
      failBool:error];
  }

  // Deleting the device from the set can still leave it around for a few seconds.
  // This could race with methods that may reallocate the newly-deleted device
  // So we should wait for the device to no longer be present in the underlying set.
  BOOL wasRemovedFromDeviceSet = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBSimulatorControlGlobalConfiguration.regularTimeout untilTrue:^ BOOL {
    NSOrderedSet *udidSet = [self.allSimulators valueForKey:@"udid"];
    return ![udidSet containsObject:udid];
  }];
  if (!wasRemovedFromDeviceSet) {
    return [[[[FBSimulatorError
      describeFormat:@"Simulator with UDID %@ should have been removed from set but wasn't.", udid]
      inSimulator:simulator]
      logger:self.logger]
      failBool:error];
  }
  
  return YES;
}

- (BOOL)killSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  NSParameterAssert(simulator);
  NSParameterAssert(simulator.device.deviceSet != self.deviceSet);

  return [self.simulatorTerminationStrategy killSimulators:@[simulator] withError:error] != nil;
}

- (NSArray *)killAllWithError:(NSError **)error
{
  return [self.simulatorTerminationStrategy killSimulators:self.allSimulators withError:error];
}

- (BOOL)killSpuriousSimulatorsWithError:(NSError **)error
{
  return [self.simulatorTerminationStrategy killSpuriousSimulatorsWithError:error];
}

- (NSArray *)deleteAllWithError:(NSError **)error
{
  return [self deleteSimulators:self.allSimulators withError:error];
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

#pragma mark FBJSONSerializationDescribeable Protocol

- (id)jsonSerializableRepresentation
{
  return [self.allSimulators valueForKey:NSStringFromSelector(@selector(jsonSerializableRepresentation))];
}

#pragma mark Private Methods

- (NSArray *)deleteSimulators:(NSArray *)simulators withError:(NSError **)error
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

- (NSArray *)eraseSimulators:(NSArray *)simulators withError:(NSError **)error
{
  // Kill the Simulators before erasing them.
  NSError *innerError = nil;
  if (![self.simulatorTerminationStrategy killSimulators:simulators withError:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  // Then Erase them.
  for (FBSimulator *simulator in simulators) {
    if (![simulator eraseWithError:&innerError]) {
      return [FBSimulatorError failWithError:innerError errorOut:error];
    }
  }
  return simulators;
}

+ (NSDictionary *)keySimulatorsByUDID:(NSArray *)simulators
{
  NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
  for (FBSimulator *simulator in simulators) {
    dictionary[simulator.udid] = simulator;
  }
  return [dictionary copy];
}

#pragma mark - Properties

#pragma mark Public

- (NSArray *)allSimulators
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

- (NSArray *)launchedSimulators
{
  return [self.allSimulators filteredArrayUsingPredicate:FBSimulatorPredicates.launched];
}

#pragma mark Private

- (FBSimulatorTerminationStrategy *)simulatorTerminationStrategy
{
  return [FBSimulatorTerminationStrategy withConfiguration:self.configuration processQuery:self.processQuery logger:self.logger];
}

- (FBCoreSimulatorTerminationStrategy *)coreSimulatorTerminationStrategy
{
  return [FBCoreSimulatorTerminationStrategy withProcessQuery:self.processQuery logger:self.logger];
}

@end

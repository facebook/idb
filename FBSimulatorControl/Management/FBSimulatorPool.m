/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorPool.h"
#import "FBSimulatorPool+Private.h"

#import <CoreSimulator/NSUserDefaults-SimDefaults.h>
#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBCoreSimulatorNotifier.h"
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
#import "FBSimulatorTerminationStrategy.h"
#import "FBTaskExecutor+Convenience.h"
#import "FBTaskExecutor.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

static NSTimeInterval const FBSimulatorPoolDefaultWait = 30.0;

@implementation FBSimulatorPool

#pragma mark - Initializers

+ (instancetype)poolWithConfiguration:(FBSimulatorControlConfiguration *)configuration error:(NSError **)error
{
  NSError *innerError = nil;
  SimDeviceSet *deviceSet = [self createDeviceSetWithConfiguration:configuration error:&innerError];
  if (!deviceSet) {
    return [[[FBSimulatorError describe:@"Failed to create device set"] causedBy:innerError] fail:error];
  }

  FBSimulatorPool *pool = [[FBSimulatorPool alloc] initWithConfiguration:configuration deviceSet:deviceSet];
  if (![pool performPoolPreconditionsWithError:&innerError]) {
    return [[[FBSimulatorError describe:@"Failed meet pool preconditions"] causedBy:innerError] fail:error];
  }
  return pool;
}

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration deviceSet:(SimDeviceSet *)deviceSet
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _allocatedUDIDs = [NSMutableOrderedSet new];
  _allocationOptions = [NSMutableDictionary dictionary];
  _inflatedSimulators = [NSMutableDictionary dictionary];
  _processQuery = [FBProcessQuery new];
  _deviceSet = deviceSet;

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
    ? [SimDeviceSet setForSetPath:configuration.deviceSetPath]
    : [SimDeviceSet defaultSet];
}

- (BOOL)performPoolPreconditionsWithError:(NSError **)error
{
  NSError *innerError = nil;
  BOOL killSpuriousCoreSimulatorServices = (self.configuration.options & FBSimulatorManagementOptionsKillSpuriousCoreSimulatorServices) == FBSimulatorManagementOptionsKillSpuriousCoreSimulatorServices;
  if (killSpuriousCoreSimulatorServices) {
    if (![self.terminationStrategy killSpuriousCoreSimulatorServicesWithError:&innerError]) {
      return [[[FBSimulatorError describe:@"Failed to kill spurious CoreSimulatorServices"] causedBy:innerError] failBool:error];
    }
  }

  BOOL deleteOnStart = (self.configuration.options & FBSimulatorManagementOptionsDeleteAllOnFirstStart) == FBSimulatorManagementOptionsDeleteAllOnFirstStart;
  if (deleteOnStart) {
    if (![self deleteAllWithError:&innerError]) {
      return [[[[FBSimulatorError describe:@"Failed to delete all simulators"] causedBy:innerError] recursiveDescription] failBool:error];
    }
  }

  // Deletion requires killing, so don't duplicate killing
  BOOL killSpuriousSimulators = (self.configuration.options & FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart) == FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart;
  if (killSpuriousSimulators && !deleteOnStart) {
    BOOL failOnSpuriousKillFail = (self.configuration.options & FBSimulatorManagementOptionsIgnoreSpuriousKillFail) != FBSimulatorManagementOptionsIgnoreSpuriousKillFail;
    if (![self.terminationStrategy killSpuriousSimulatorsWithError:&innerError] && failOnSpuriousKillFail) {
      return [[[FBSimulatorError describe:@"Failed to kill spurious simulators"] causedBy:innerError] failBool:error];
    }

    if (![self.terminationStrategy ensureConsistencyForSimulators:self.allSimulators withError:&innerError]) {
      return [[[FBSimulatorError describe:@"Failed to ensure simulator consistency"] causedBy:innerError] failBool:error];
    }
  }

  return YES;
}

#pragma mark - Public Accessors

- (NSArray *)allSimulators
{
  // Inflate new simulators that have come along since last time.
  NSArray *simDevices = self.deviceSet.availableDevices;
  for (SimDevice *device in simDevices) {
    NSString *udid = device.UDID.UUIDString;
    if (self.inflatedSimulators[udid]) {
      continue;
    }
    FBSimulator *simulator = [FBSimulator fromSimDevice:device configuration:nil pool:self query:self.processQuery];
    self.inflatedSimulators[udid] = simulator;
  }

  // Cull Simulators that should have gone away.
  NSArray *currentSimulatorUDIDs = [simDevices valueForKeyPath:@"UDID.UUIDString"];
  NSMutableSet *cullSet = [NSMutableSet setWithArray:self.inflatedSimulators.allKeys];
  [cullSet minusSet:[NSSet setWithArray:currentSimulatorUDIDs]];
  [self.inflatedSimulators removeObjectsForKeys:cullSet.allObjects];

  return [self.inflatedSimulators objectsForKeys:currentSimulatorUDIDs notFoundMarker:NSNull.null];
}

- (FBSimulatorTerminationStrategy *)terminationStrategy
{
  // `self.allSimulators` is not a constant for the lifetime of self, so should be fetched on all usages.
  return [FBSimulatorTerminationStrategy withConfiguration:self.configuration processQuery:self.processQuery];
}

#pragma mark - Public Methods

- (FBSimulator *)allocateSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration options:(FBSimulatorAllocationOptions)options error:(NSError **)error;
{
  FBSimulator *simulator = [self obtainSimulatorWithConfiguration:configuration options:options error:error];
  if (!simulator) {
    return nil;
  }

  NSError *innerError = nil;
  if (![self prepareSimulatorForUsage:simulator configuration:configuration options:options error:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  [self pushAllocation:simulator options:options];
  return simulator;
}

- (BOOL)freeSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  FBSimulatorAllocationOptions options = [self popAllocation:simulator];

  // Killing is a pre-requesite for deleting/erasing
  NSError *innerError = nil;
  if (![self.terminationStrategy killSimulators:@[simulator] withError:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError description:@"Failed to Free Device in Killing Device" errorOut:error];
  }

  // When Deleting on Free, there's no point in erasing first, so return early.
  BOOL deleteOnFree = (options & FBSimulatorAllocationOptionsDeleteOnFree) == FBSimulatorAllocationOptionsDeleteOnFree;
  if (deleteOnFree) {
    if (![self deleteSimulator:simulator withError:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError description:@"Failed to Free Device in Deleting Device" errorOut:error];
    }
    return YES;
  }

  BOOL eraseOnFree = (self.configuration.options & FBSimulatorAllocationOptionsEraseOnFree) == FBSimulatorAllocationOptionsEraseOnFree;
  if (eraseOnFree) {
    if (![simulator eraseWithError:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError description:@"Failed to Free Device in Erasing Device" errorOut:error];
    }
    return YES;
  }

  return YES;
}

- (NSArray *)killAllWithError:(NSError **)error
{
  return [self.terminationStrategy killSimulators:self.allSimulators withError:error];
}

- (BOOL)killSpuriousSimulatorsWithError:(NSError **)error
{
  return [self.terminationStrategy killSpuriousSimulatorsWithError:error];
}

- (NSArray *)deleteAllWithError:(NSError **)error
{
  // Attempt to kill any and all simulators belonging to this pool before deleting.
  NSError *innerError = nil;
  if (![self killAllWithError:&innerError]) {
    return [[[FBSimulatorError describe:@"Failed to kill all simulators prior to delete all"] causedBy:innerError] fail:error];
  }

  return [self deleteSimulators:self.allSimulators withError:error];
}

#pragma mark - Private

- (BOOL)deleteSimulator:(FBSimulator *)simulator withError:(NSError **)error
{
  NSString *udid = simulator.udid;

  NSError *innerError = nil;
  if (![self.deviceSet deleteDevice:simulator.device error:&innerError]) {
    return [[[[FBSimulatorError describeFormat:@"Failed to Delete simulator %@", simulator] causedBy:innerError] inSimulator:simulator] failBool:error];
  }

  // Deleting the device from the set can still leave it around for a few seconds.
  // This could race with methods that may reallocate the newly-deleted device
  // So we should wait for the device to no longer be present in the underlying set.
  BOOL wasRemovedFromDeviceSet = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBSimulatorPoolDefaultWait untilTrue:^ BOOL {
    NSOrderedSet *udidSet = [self.allSimulators valueForKey:@"udid"];
    return ![udidSet containsObject:udid];
  }];

  if (!wasRemovedFromDeviceSet) {
    return [[[FBSimulatorError describeFormat:@"Simulator with UDID %@ should have been removed from set but wasn't.", udid] inSimulator:simulator] failBool:error];
  }

  return YES;
}

- (NSArray *)deleteSimulators:(NSArray *)simulators withError:(NSError **)error
{
  NSError *innerError = nil;
  NSMutableArray *deletedSimulatorNames = [NSMutableArray array];
  for (FBSimulator *simulator in simulators) {
    NSString *simulatorName = simulator.name;
    if (![self deleteSimulator:simulator withError:&innerError]) {
      return [FBSimulatorError failWithError:innerError errorOut:error];
    }
    [deletedSimulatorNames addObject:simulatorName];
  }
  return [deletedSimulatorNames copy];
}

- (NSArray *)eraseSimulators:(NSArray *)simulators withError:(NSError **)error
{
  NSError *innerError = nil;
  // Kill all the simulators first
  if (![self.terminationStrategy killSimulators:simulators withError:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  // Then erase.
  for (FBSimulator *simulator in simulators) {
    if (![simulator eraseWithError:&innerError]) {
      return [FBSimulatorError failWithError:innerError errorOut:error];
    }
  }
  return simulators;
}

- (FBSimulator *)obtainSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration options:(FBSimulatorAllocationOptions)options error:(NSError **)error
{
  BOOL reuse = (options & FBSimulatorAllocationOptionsReuse) == FBSimulatorAllocationOptionsReuse;
  if (reuse) {
    FBSimulator *simulator = [self findUnallocatedSimulatorWithConfiguration:configuration];
    if (simulator) {
      return simulator;
    }
  }

  BOOL create = (options & FBSimulatorAllocationOptionsCreate) == FBSimulatorAllocationOptionsCreate;
  if (!create) {
    return [[FBSimulatorError describeFormat:@"Could not obtain a simulator as the options don't allow creation"] fail:error];
  }
  return [self createSimulatorWithConfiguration:configuration error:error];
}

- (FBSimulator *)findUnallocatedSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration
{
  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [FBSimulatorPredicates unallocatedByPool:self],
    [FBSimulatorPredicates matchingConfiguration:configuration]
  ]];
  return [[self.allSimulators filteredArrayUsingPredicate:predicate] firstObject];
}

- (FBSimulator *)createSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration error:(NSError **)error
{
  NSString *targetName = configuration.deviceName;
  SimDeviceType *targetType = configuration.deviceType;
  SimRuntime *targetRuntime = configuration.runtime;

  NSError *innerError = nil;
  SimDevice *device = [self.deviceSet createDeviceWithType:targetType runtime:targetRuntime name:targetName error:&innerError];
  if (!device) {
    return [[[FBSimulatorError describeFormat:@"Failed to create a simulator with the name %@, runtime %@, type %@", targetName, targetRuntime, targetType] causedBy:innerError] fail:error];
  }
  FBSimulator *simulator = [FBSimulatorPool keySimulatorsByUDID:self.allSimulators][device.UDID.UUIDString];
  simulator.configuration = configuration;
  NSAssert(simulator, @"Expected simulator with name %@ to be inflated into pool", targetName);
  return simulator;
}

- (BOOL)prepareSimulatorForUsage:(FBSimulator *)simulator configuration:(FBSimulatorConfiguration *)configuration options:(FBSimulatorAllocationOptions)options error:(NSError **)error
{
  // In order to erase, the device *must* be shutdown first.
  BOOL shutdown = (options & FBSimulatorAllocationOptionsShutdownOnAllocate) == FBSimulatorAllocationOptionsShutdownOnAllocate;
  BOOL erase = (options & FBSimulatorAllocationOptionsEraseOnAllocate) == FBSimulatorAllocationOptionsEraseOnAllocate;
  NSError *innerError = nil;
  if ((shutdown || erase) & ![self.terminationStrategy killSimulators:@[simulator] withError:&innerError]) {
    return [[[[FBSimulatorError describe:@"Failed to kill a Simulator when allocating it"] causedBy:innerError] inSimulator:simulator] failBool:error];
  }

  // Now we have a device that is shutdown, we should erase it.
  // Only erase if the simulator was allocated with reuse, otherwise it is a fresh Simulator that won't need erasing.
  BOOL reuse = (options & FBSimulatorAllocationOptionsReuse) == FBSimulatorAllocationOptionsReuse;
  if (reuse && erase && ![simulator.device eraseContentsAndSettingsWithError:&innerError]) {
    return [[[[FBSimulatorError describe:@"Failed to erase a Simulator when allocating it"] causedBy:innerError] inSimulator:simulator] failBool:error];
  }

  // Do the other configuration that is dependent on a shutdown Simulator.
  if (shutdown || erase) {
    if (configuration.locale && ![[simulator.interact setLocale:configuration.locale] performInteractionWithError:&innerError]) {
      return [[[[FBSimulatorError describe:@"Failed to set the locale on a Simulator when allocating it"] causedBy:innerError] inSimulator:simulator] failBool:error];
    }
    if (![[simulator.interact setupKeyboard] performInteractionWithError:&innerError]) {
      return [[[[FBSimulatorError describe:@"Failed to setup the keyboard of a Simulator when allocating it"] causedBy:innerError] inSimulator:simulator] failBool:error];
    }
  }

  return YES;
}

- (void)pushAllocation:(FBSimulator *)simulator options:(FBSimulatorAllocationOptions)options
{
  NSParameterAssert(simulator);
  NSParameterAssert(![self.allocatedUDIDs containsObject:simulator.udid]);
  NSParameterAssert(!self.allocationOptions[simulator.udid]);

  [self.allocatedUDIDs addObject:simulator.udid];
  self.allocationOptions[simulator.udid] = @(options);
}

- (FBSimulatorAllocationOptions)popAllocation:(FBSimulator *)simulator
{
  NSParameterAssert(simulator);
  NSParameterAssert([self.allocatedUDIDs containsObject:simulator.udid]);
  NSParameterAssert(self.allocationOptions[simulator.udid]);

  [self.allocatedUDIDs removeObject:simulator.udid];
  FBSimulatorAllocationOptions options = [self.allocationOptions[simulator.udid] unsignedIntegerValue];
  [self.allocationOptions removeObjectForKey:simulator.udid];
  return options;
}

#pragma mark - Helpers

+ (NSDictionary *)keySimulatorsByUDID:(NSArray *)simulators
{
  NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
  for (FBSimulator *simulator in simulators) {
    dictionary[simulator.udid] = simulator;
  }
  return [dictionary copy];
}

@end

@implementation FBSimulatorPool (Fetchers)

- (NSArray *)allocatedSimulators
{
  return [self.allSimulators filteredArrayUsingPredicate:[FBSimulatorPredicates allocatedByPool:self]];
}

- (NSArray *)unallocatedSimulators
{
  return [self.allSimulators filteredArrayUsingPredicate:[FBSimulatorPredicates unallocatedByPool:self]];
}

- (NSArray *)launchedSimulators
{
  return [self.allSimulators filteredArrayUsingPredicate:FBSimulatorPredicates.launched];
}

@end

@implementation FBSimulatorPool (Debug)

- (NSString *)debugDescription
{
  NSMutableString *description = [NSMutableString string];
  [description appendFormat:@"SimDevices: %@", [self.deviceSet.availableDevices description]];
  [description appendFormat:@"\nAll Simulators: %@", [self.allSimulators description]];
  [description appendFormat:@"\nAllocated Simulators: %@ \n\n", [self.allocatedSimulators description]];
  [description appendFormat:@"\nSimulator Processes: %@ \n\n", [self activeSimulatorProcessesWithError:nil]];
  return description;
}

- (void)startLoggingSimDeviceSetInteractions:(id<FBSimulatorLogger>)logger;
{
  [FBCoreSimulatorNotifier notifierForPool:self block:^(NSDictionary *info) {
    [logger logMessage:@"Device Set Changed: %@", info];
  }];
}

- (NSString *)activeSimulatorProcessesWithError:(NSError *)error
{
  return [[[FBTaskExecutor.sharedInstance
    taskWithLaunchPath:@"/usr/bin/pgrep" arguments:@[@"-lf", @"Simulator"]]
    startSynchronouslyWithTimeout:8]
    stdOut];
}

@end

void FBSetSimulatorLoggingEnabled(BOOL enabled)
{
  NSUserDefaults *simulatorDefaults = [NSUserDefaults simulatorDefaults];
  [simulatorDefaults setBool:enabled forKey:@"DebugLogging"];
}

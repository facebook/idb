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

#import "FBCoreSimulatorNotifier.h"
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

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

static NSTimeInterval const FBSimulatorPoolDefaultWait = 30.0;

@implementation FBSimulatorPool

#pragma mark - Initializers

+ (instancetype)poolWithConfiguration:(FBSimulatorControlConfiguration *)configuration deviceSet:(SimDeviceSet *)deviceSet
{
  FBSimulatorPool *pool = [self new];
  pool.deviceSet = deviceSet;
  pool.configuration = configuration;
  pool.allocatedUDIDs = [NSMutableOrderedSet new];
  return pool;
}

#pragma mark - Public Accessors

- (NSOrderedSet *)allSimulators
{
  NSMutableOrderedSet *simulators = [NSMutableOrderedSet orderedSet];
  for (SimDevice *device in self.deviceSet.availableDevices) {
    [simulators addObject:[FBSimulator inflateFromSimDevice:device configuration:self.configuration]];
  }
  [simulators sortUsingComparator:^NSComparisonResult(FBSimulator *left, FBSimulator *right) {
    return [left.name compare:right.name];
  }];

  return [simulators copy];
}

#pragma mark - Public Methods

- (FBSimulator *)simulatorWithUDID:(NSString *)udidString
{
  NSParameterAssert(udidString);
  for (FBSimulator *simulator in self.deviceSet.availableDevices) {
    if ([simulator.udid isEqualToString:udidString]) {
      return simulator;
    }
  }
  return nil;
}

- (FBManagedSimulator *)allocateSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration error:(NSError **)error
{
  FBManagedSimulator *simulator = [self findOrCreateSimulatorWithConfiguration:configuration error:error];
  if (!simulator) {
    return nil;
  }
  if (![self prepareSimulatorForUsage:simulator configuration:configuration error:error]) {
    return nil;
  }

  [self.allocatedUDIDs addObject:simulator.udid];
  return simulator;
}

- (BOOL)freeSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  [self.allocatedUDIDs removeObject:simulator.udid];

  NSError *innerError = nil;
  if (![self killSimulators:@[simulator] withError:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError description:@"Failed to Free Device in Killing Device" errorOut:error];
  }

  // When Deleting on Free, there's no point in erasing first, so return early.
  BOOL deleteOnFree = (self.configuration.options & FBSimulatorManagementOptionsDeleteOnFree) == FBSimulatorManagementOptionsDeleteOnFree;
  if (deleteOnFree) {
    if (![self deleteSimulator:simulator withError:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError description:@"Failed to Free Device in Deleting Device" errorOut:error];
    }
    return YES;
  }

  BOOL eraseOnFree = (self.configuration.options & FBSimulatorManagementOptionsEraseOnFree) == FBSimulatorManagementOptionsEraseOnFree;
  if (eraseOnFree) {
    if (![self eraseSimulator:simulator withError:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError description:@"Failed to Free Device in Erasing Device" errorOut:error];
    }
    return YES;
  }

  return YES;
}

- (NSArray *)killManagedSimulatorsWithError:(NSError **)error
{
  return [self killSimulators:[self.allSimulatorsInPool.array copy] withError:error];
}

- (NSArray *)killPooledSimulatorsWithError:(NSError **)error
{
  return [self killSimulators:[self.allPooledSimulators.array copy] withError:error];
}

- (NSArray *)killUnmanagedSimulatorsWithError:(NSError **)error
{
  // We should also kill Simulators that are in totally the wrong Simulator binary.
  // Overlapping Xcode instances can't run on the same machine
  NSError *innerError = nil;
  if (![self blanketKillSimulatorsFromDifferentXcodeVersion:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  // We want to blanket kill all the Simulator Applications that belong to the current Xcode version
  // but aren't launched in the automated CurretnDeviceUDID way.
  if (![self blanketKillSimulatorAppsWithPidFilter:@"grep -v CurrentDeviceUDID |" error:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  // This will make sure that the devices are killed themselves
  return [self shutdownSimulators:[self.unmanagedSimulators.array copy] withError:error];
}

- (NSArray *)eraseManagedSimulatorsWithError:(NSError **)error
{
  return [self eraseSimulators:[self.allPooledSimulators.array copy] withError:error];
}

- (NSArray *)deleteManagedSimulatorsWithError:(NSError **)error
{
  return [self deleteSimulators:[self.allSimulatorsInPool.array copy] withError:error];
}

- (NSArray *)deletePooledSimulatorsWithError:(NSError **)error
{
  return [self deleteSimulators:[self.allPooledSimulators.array copy] withError:error];
}

#pragma mark - Private

- (BOOL)waitForSimulator:(FBSimulator *)simulator toChangeToState:(FBSimulatorState)simulatorState withError:(NSError **)error
{
  BOOL didChangeState = [simulator waitOnState:simulatorState];
  if (!didChangeState) {
    return [[FBSimulatorError describeFormat:
      @"Simulator was not in expected %@ state, got %@",
      [FBSimulator stateStringFromSimulatorState:simulatorState],
      [FBSimulator stateStringFromSimulatorState:simulator.state]
    ] failBool:error];
  }

  return YES;
}

- (BOOL)eraseSimulator:(FBSimulator *)simulator withError:(NSError **)error
{
  NSError *innerError = nil;
  if (![simulator.device eraseContentsAndSettingsWithError:&innerError]) {
    return [[[[FBSimulatorError describeFormat:@"Failed to Erase Contents and Settings %@", simulator] causedBy:innerError] inSimulator:simulator] failBool:error];
  }
  return YES;
}

- (BOOL)deleteSimulator:(FBSimulator *)simulator withError:(NSError **)error
{
  NSString *udid = simulator.udid;

  NSError *innerError = nil;
  if (![self.deviceSet deleteDevice:simulator.device error:&innerError]) {
    return [[[[FBSimulatorError describeFormat:@"Failed to Delete simulator %@", simulator] causedBy:innerError] inSimulator:simulator] failBool:error];
  }

  // Deleting the device from the set can still leave it around for a few seconds.
  // in order to prevent racing with methods that may reallocate the newly-deleted device, we should wait for the device to no longer be present in the set.
  BOOL wasRemovedFromDeviceSet = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBSimulatorPoolDefaultWait untilTrue:^ BOOL {
    NSOrderedSet *udidSet = [self.allPooledSimulators valueForKey:@"udid"];
    return ![udidSet containsObject:udid];
  }];

  if (!wasRemovedFromDeviceSet) {
    return [[[FBSimulatorError describeFormat:@"Simulator with UDID %@ should have been removed from set but wasn't.", udid] inSimulator:simulator] failBool:error];
  }

  return YES;
}

- (NSArray *)shutdownSimulators:(NSArray *)simulators withError:(NSError **)error
{
  NSError *innerError = nil;
  for (FBSimulator *simulator in simulators) {
    if (![self safeShutdown:simulator withError:&innerError]) {
      return [FBSimulatorError failWithError:innerError errorOut:error];
    }
  }
  return simulators;
}

- (NSArray *)deleteSimulators:(NSArray *)simulators withError:(NSError **)error
{
  NSError *innerError = nil;
  if (![self killSimulators:simulators withError:&innerError]) {
    return [FBSimulatorError failWithError:innerError description:@"Failed to kill simulators before deletion." errorOut:error];
  }

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

- (NSArray *)killSimulators:(NSArray *)simulators withError:(NSError **)error
{
  // Return early if there isn't anything to kill
  if (simulators.count < 1) {
    return simulators;
  }

  NSMutableString *grepComponents = [NSMutableString string];
  [grepComponents appendFormat:@"grep CurrentDeviceUDID | grep"];
  for (FBSimulator *simulator in simulators) {
    [grepComponents appendFormat:@" -e %@ ", simulator.udid];
  }
  [grepComponents appendString:@" | "];

  // We want to blanket kill all the Managed Simulators that are launched by us
  // That means that they contain device UDIDs that we own.
  NSError *innerError = nil;
  if (![self blanketKillSimulatorAppsWithPidFilter:grepComponents error:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  NSArray *devices = [simulators valueForKey:@"device"];
  return [self shutdownSimulators:simulators withError:error];
}

- (NSArray *)eraseSimulators:(NSArray *)simulators withError:(NSError **)error
{
  NSError *innerError = nil;
  // Kill all the simulators first
  if (![self killSimulators:simulators withError:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  // Then erase.
  for (FBSimulator *simulator in simulators) {
    if (![self eraseSimulator:simulator withError:&innerError]) {
      return [FBSimulatorError failWithError:innerError errorOut:error];
    }
  }
  return simulators;
}

- (BOOL)safeShutdown:(FBSimulator *)simulator withError:(NSError **)error
{
  // Calling shutdown when already shutdown should be avoided (if detected).
  if (simulator.state == FBSimulatorStateShutdown) {
    return YES;
  }

  // Code 159 (Xcode 7) or 146 (Xcode 6) is 'Unable to shutdown device in current state: Shutdown'
  // We can safely ignore this and then confirm that the simulator is shutdown
  NSError *innerError = nil;
  if (![simulator.device shutdownWithError:&innerError] && innerError.code != 159 && innerError.code != 146) {
    return [FBSimulatorError failBoolWithError:innerError description:@"Simulator could not be shutdown" errorOut:error];
  }

  // We rely on the catch-all-non-manged kill command to do the dirty work.
  // This will confirm that all these simulators are shutdown.
  return [self waitForSimulator:simulator toChangeToState:FBSimulatorStateShutdown withError:error];
}

- (FBManagedSimulator *)findOrCreateSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration error:(NSError **)error
{
  return [self findSimulatorWithConfiguration:configuration]
      ?: [self createSimulatorWithConfiguration:configuration error:error];
}

- (FBManagedSimulator *)findSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration
{
  NSString *deviceName = [self targetNameForConfiguration:configuration];
  for (FBManagedSimulator *simulator in self.unallocatedSimulators) {
    if ([simulator.name isEqualToString:deviceName]) {
      return simulator;
    }
  }
  return nil;
}

- (FBManagedSimulator *)createSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration error:(NSError **)error
{
  NSString *targetName = [self targetNameForConfiguration:configuration];
  SimDeviceType *targetType = configuration.deviceType;
  SimRuntime *targetRuntime = configuration.runtime;

  NSError *innerError = nil;
  SimDevice *device = [self.deviceSet createDeviceWithType:targetType runtime:targetRuntime name:targetName error:&innerError];
  if (!device) {
    return [[[FBSimulatorError describeFormat:@"Failed to create a simulator with the name %@", targetName] causedBy:innerError] fail:error];
  }
  FBManagedSimulator *simulator = [FBSimulatorPool keySimulatorsByUDID:self.allSimulatorsInPool][device.UDID.UUIDString];
  simulator.configuration = configuration;
  NSAssert(simulator, @"Expected simulator with name %@ to be inflated into pool", targetName);
  return simulator;
}

- (BOOL)prepareSimulatorForUsage:(FBSimulator *)simulator configuration:(FBSimulatorConfiguration *)configuration error:(NSError **)error
{
  NSError *innerError = nil;

  // If the device is in a strange state, we should bail now
  if (simulator.state == FBSimulatorStateUnknown) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Failed to prepare simulator for usage as it is in an unknown state" errorOut:error];
  }
  // Xcode 7 has a 'Creating' step that we should wait on before confirming the simulator is ready.
  if (simulator.state == FBSimulatorStateCreating) {
    // Once the device is 'Shutdown'
    if ([self waitForSimulator:simulator toChangeToState:FBSimulatorStateShutdown withError:&innerError]) {
      return YES;
    }

    // In Xcode 7 we can get stuck in the 'Creating' step as well, its possible that we can recover from this by erasing
    if (![self eraseSimulator:simulator withError:&innerError]) {
      return [[[[FBSimulatorError describe:@"Failed trying to prepare simulator for usage by erasing a stuck 'Creating' simulator %@"] causedBy:innerError] inSimulator:simulator] failBool:error];
    }

    // If a device has been erased, we should wait for it to actually be shutdown.
    if ([self waitForSimulator:simulator toChangeToState:FBSimulatorStateShutdown withError:&innerError]) {
      return YES;
    }

    // This simulator can't be fixed: fail
    return [[[[FBSimulatorError describe:@"Failed trying to wait for a 'Creating' simulator to be shutdown after being erased"] causedBy:innerError] inSimulator:simulator] failBool:error];
  }

  // If the device is not shutdown, kill it.
  if (simulator.state != FBSimulatorStateShutdown) {
    if (![self killSimulators:@[simulator] withError:error]) {
      return [[[[FBSimulatorError describe:@"Failed to prepare simulator for usage when shutting it down"] causedBy:innerError] inSimulator:simulator] failBool:error];
    }
  }

  // Wait for it to be truly shutdown.
  if (![self waitForSimulator:simulator toChangeToState:FBSimulatorStateShutdown withError:&innerError]) {
    return [[[[FBSimulatorError describe:@"Failed to wait for simulator preparation to shutdown device"] causedBy:innerError] inSimulator:simulator] failBool:error];
  }

  // Now we have a device that is shutdown, we should erase it.
  if (![simulator.device eraseContentsAndSettingsWithError:&innerError]) {
    return [[[[FBSimulatorError describe:@"Failed to prepare simulator for usage when erasing it"] causedBy:innerError] inSimulator:simulator] failBool:error];
  }

  // Do the other, non-session based setup steps.
  if (![[simulator.interact configureWith:configuration] performInteractionWithError:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  return YES;
}

#pragma mark - Helpers

- (BOOL)blanketKillSimulatorsFromDifferentXcodeVersion:(NSError **)error
{
  // All Simulator Versions from Xcode 5-7, end in Simulator.app
  // This command kills all Simulator.app binaries that *don't* match the current Simulator Binary Path.
  NSString *simulatorBinaryPath = self.configuration.simulatorApplication.binary.path;
  NSString *command = [NSString stringWithFormat:
    @"pgrep -lf Simulator.app | grep -v %@ | awk '{print $1}' | xargs kill",
   [FBTaskExecutor escapePathForShell:simulatorBinaryPath]
  ];

  NSError *innerError = nil;
  if (![self blanketKillSimulatorAppsPidProducingCommand:command error:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError description:@"Could not kill non-current xcode simulators" errorOut:error];
  }
  return YES;
}

- (BOOL)blanketKillSimulatorAppsWithPidFilter:(NSString *)pidFilter error:(NSError **)error
{
  NSString *simulatorBinaryPath = self.configuration.simulatorApplication.binary.path;
  NSString *command = [NSString stringWithFormat:
    @"pgrep -lf %@ | %@ awk '{print $1}'",
    [FBTaskExecutor escapePathForShell:simulatorBinaryPath],
    pidFilter
  ];

  NSError *innerError = nil;
  if (![self blanketKillSimulatorAppsPidProducingCommand:command error:&innerError]) {
    return [[[FBSimulatorError describeFormat:@"Could not kill simulators with pid filter %@", pidFilter] causedBy:innerError] failBool:error];
  }
  return YES;
}

- (BOOL)blanketKillSimulatorAppsPidProducingCommand:(NSString *)commandForPids error:(NSError **)error
{
  FBTaskExecutor *executor = FBTaskExecutor.sharedInstance;
  NSString *command = [NSString stringWithFormat:
    @"%@ | xargs kill",
    commandForPids
  ];
  NSError *innerError = nil;
  if (![executor executeShellCommand:command returningError:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError description:@"Failed to Kill Simulator Process" errorOut:error];
  }
  return YES;
}

- (NSString *)targetNameForConfiguration:(FBSimulatorConfiguration *)configuration
{
  SimDeviceType *targetType = configuration.deviceType;
  SimRuntime *targetRuntime = configuration.runtime;
  NSString *targetName = [NSString stringWithFormat:
    @"%@_%ld_%ld_%@_%@",
    self.configuration.namePrefix,
    self.configuration.bucketID,
    [self nextAvailableOffsetForDeviceType:targetType runtime:targetRuntime],
    targetType.name,
    targetRuntime.versionString
  ];
  return targetName;
}

- (NSInteger)nextAvailableOffsetForDeviceType:(SimDeviceType *)deviceType runtime:(SimRuntime *)runtime
{
  NSMutableIndexSet *indeces = [NSMutableIndexSet indexSet];
  for (FBManagedSimulator *simulator in self.allocatedSimulators) {
    if (![simulator.device.deviceType isEqual:deviceType]) {
      continue;
    }
    if (![simulator.device.runtime isEqual:runtime]) {
      continue;
    }
    [indeces addIndex:simulator.offset];
  }
  for (NSInteger index = 0; index < INT_MAX; index++) {
    if (![indeces containsIndex:index]) {
      return index;
    }
  }
  return -1;
}

+ (NSDictionary *)keySimulatorsByUDID:(NSOrderedSet *)simulators
{
  NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
  for (FBSimulator *simulator in simulators) {
    dictionary[simulator.udid] = simulator;
  }
  return [dictionary copy];
}

@end

@implementation FBSimulatorPool (Fetchers)

- (NSString *)deviceUDIDWithName:(NSString *)deviceName simulatorSDK:(NSString *)simulatorSDK
{
  for (FBSimulator *simulator in self.allSimulators) {
    if (![simulator.name isEqualToString:deviceName]) {
      continue;
    }
    if (!simulatorSDK) {
      return simulator.udid;
    }
    if ([simulator.device.runtime.versionString isEqualToString:simulatorSDK]) {
      return simulator.udid;
    }
  }
  return nil;
}

- (FBSimulator *)allocatedSimulatorWithDeviceType:(NSString *)deviceType
{
  for (FBSimulator *simulator in self.allSimulatorsInPool) {
    if ([simulator.device.deviceType.name isEqualToString:deviceType]) {
      return simulator;
    }
  }
  return nil;
}

- (NSOrderedSet *)allSimulatorsInPool
{
  NSPredicate *predicate = [FBSimulatorPredicates managedByPool:self];
  NSOrderedSet *set = [self.allSimulators filteredOrderedSetUsingPredicate:predicate];
  [set.array makeObjectsPerformSelector:@selector(setPool:) withObject:self];
  return set;
}

- (NSOrderedSet *)allPooledSimulators
{
  return [self.allSimulators filteredOrderedSetUsingPredicate:FBSimulatorPredicates.managed];
}

- (NSOrderedSet *)allocatedSimulators
{
  NSPredicate *predicate = [FBSimulatorPredicates allocatedByPool:self];
  return [[[self.allSimulators copy] filteredOrderedSetUsingPredicate:predicate] reversedOrderedSet];
}

- (NSOrderedSet *)unallocatedSimulators
{
  NSPredicate *predicate = [FBSimulatorPredicates unallocatedByPool:self];
  return [self.allSimulators filteredOrderedSetUsingPredicate:predicate];
}

- (NSOrderedSet *)unmanagedSimulators
{
  return [self.allSimulators filteredOrderedSetUsingPredicate:FBSimulatorPredicates.unmanaged];
}

- (NSOrderedSet *)launchedSimulators
{
  return [self.allSimulators filteredOrderedSetUsingPredicate:FBSimulatorPredicates.launched];
}

@end

@implementation FBSimulatorPool (Debug)

- (NSString *)debugDescription
{
  NSMutableString *description = [NSMutableString string];
  [description appendFormat:@"SimDevices: %@", [self.deviceSet.availableDevices description]];
  [description appendFormat:@"\nAllocated Devices: %@", [self.allocatedSimulators description]];
  [description appendFormat:@"\nAll Self Managed Devices: %@", [self.allSimulatorsInPool description]];
  [description appendFormat:@"\nAll Pooled Devices: %@ \n\n", [self.allPooledSimulators description]];
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

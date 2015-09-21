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
#import "FBSimulatorConfiguration+DTMobile.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction.h"
#import "FBSimulatorLogger.h"
#import "FBTaskExecutor+Convenience.h"
#import "FBTaskExecutor.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

@implementation FBSimulatorPool

#pragma mark - Initializers

+ (instancetype)poolWithConfiguration:(FBSimulatorControlConfiguration *)configuration deviceSet:(SimDeviceSet *)deviceSet
{
  FBSimulatorPool *pool = [self new];
  pool.deviceSet = deviceSet;
  pool.configuration = configuration;
  pool.allocatedWorkingSet = [NSMutableOrderedSet new];
  return pool;
}

#pragma mark - Public Accessors

- (NSOrderedSet *)allSimulatorsInPool
{
  return [self inflatePooledSimulatorsMustBeManaged:YES];
}

- (NSOrderedSet *)allPooledSimulators
{
  return [self inflatePooledSimulatorsMustBeManaged:NO];
}

- (NSOrderedSet *)allocatedSimulators
{
  // Allocated simulators are inserted at the end with O(1), we need the reverse here.
  return [[self.allocatedWorkingSet copy] reversedOrderedSet];
}

- (NSOrderedSet *)unallocatedSimulators
{
  NSMutableOrderedSet *simulators = [self.allSimulatorsInPool mutableCopy];
  [simulators minusSet:self.allocatedWorkingSet.set];
  return [simulators copy];
}

- (NSArray *)unmanagedSimulators
{
  // TODO(7849941): Figure out the equality semantics of SimDevice to see if we can use Sets to do this instead.
  NSRegularExpression *regex = [self.class managedSimulatorPoolOffsetRegex];

  NSMutableArray *unmanagedSimulators = [NSMutableArray array];
  for (SimDevice *device in self.deviceSet.availableDevices) {
    if ([regex numberOfMatchesInString:device.name options:0 range:NSMakeRange(0, device.name.length)] == 0) {
      [unmanagedSimulators addObject:device];
    }
  }

  return unmanagedSimulators;
}

#pragma mark - Public Methods

- (SimDevice *)deviceWithUDID:(NSString *)udidString
{
  NSParameterAssert(udidString);
  for (SimDevice *device in self.deviceSet.availableDevices) {
    if ([device.UDID.UUIDString isEqualToString:udidString]) {
      return device;
    }
  }
  return nil;
}

- (FBSimulator *)allocateSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration error:(NSError **)error
{
  FBSimulator *simulator = [self findOrCreateSimulatorWithConfiguration:configuration error:error];
  if (!simulator) {
    return nil;
  }
  if (![self prepareSimulatorForUsage:simulator configuration:configuration error:error]) {
    return nil;
  }

  [self.allocatedWorkingSet addObject:simulator];
  return simulator;
}

- (BOOL)freeSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  [self.allocatedWorkingSet removeObject:simulator];

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
  return [self shutdownDevices:self.unmanagedSimulators withError:error];
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

- (BOOL)waitForDevice:(SimDevice *)device toChangeToState:(FBSimulatorState)simulatorState withError:(NSError **)error
{
  BOOL didChangeState = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:30 untilTrue:^ BOOL {
    return [FBSimulator simulatorStateFromStateString:device.stateString] == simulatorState;
  }];
  if (!didChangeState) {
    return [[FBSimulatorError describeFormat:
      @"Simulator was not in expected %@ state, got %@",
      [FBSimulator stateStringFromSimulatorState:simulatorState],
      device.stateString
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
  BOOL wasRemovedFromDeviceSet = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:30 untilTrue:^ BOOL {
    NSSet *udidSet = [self.allPooledSimulators valueForKey:@"udid"];
    return ![udidSet containsObject:udid];
  }];

  if (!wasRemovedFromDeviceSet) {
    return [[[FBSimulatorError describe:@"Simulator should have been removed from set but wasn't "] inSimulator:simulator] failBool:error];
  }

  return YES;
}

- (NSArray *)shutdownDevices:(NSArray *)devices withError:(NSError **)error
{
  NSError *innerError = nil;
  for (SimDevice *device in devices) {
    if (![self safeShutdown:device withError:&innerError]) {
      return [FBSimulatorError failWithError:innerError errorOut:error];
    }
  }
  return devices;
}

- (NSArray *)deleteSimulators:(NSArray *)simulators withError:(NSError **)error
{
  NSError *innerError = nil;
  if (![self killSimulators:simulators withError:&innerError]) {
    return [FBSimulatorError failWithError:innerError description:@"Failed to kill simulator before deleting it" errorOut:error];
  }

  NSMutableArray *deletedSimulatorNames = [NSMutableArray array];
  for (FBSimulator *simulator in simulators) {
    if (![self.deviceSet deleteDevice:simulator.device error:&innerError]) {
      return [FBSimulatorError failWithError:innerError description:@"Failed to delete simulator" errorOut:error];
    }
    [deletedSimulatorNames addObject:simulator.name];
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
  return [self shutdownDevices:devices withError:error];
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

- (BOOL)safeShutdown:(SimDevice *)device withError:(NSError **)error
{
  // Calling shutdown when already shutdown should be avoided (if detected).
  if ([FBSimulator simulatorStateFromStateString:device.stateString] == FBSimulatorStateShutdown) {
    return YES;
  }

  // Code 159 (Xcode 7) or 146 (Xcode 6) is 'Unable to shutdown device in current state: Shutdown'
  // We can safely ignore this and then confirm that the simulator is shutdown
  NSError *innerError = nil;
  if (![device shutdownWithError:&innerError] && innerError.code != 159 && innerError.code != 146) {
    return [FBSimulatorError failBoolWithError:innerError description:@"Simulator could not be shutdown" errorOut:error];
  }

  // We rely on the catch-all-non-manged kill command to do the dirty work.
  // This will confirm that all these simulators are shutdown.
  return [self waitForDevice:device toChangeToState:FBSimulatorStateShutdown withError:error];
}

- (FBSimulator *)findOrCreateSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration error:(NSError **)error
{
  return [self findSimulatorWithConfiguration:configuration]
      ?: [self createSimulatorWithConfiguration:configuration error:error];
}

- (FBSimulator *)findSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration
{
  NSString *deviceName = [self targetNameForConfiguration:configuration];
  for (FBSimulator *simulator in self.unallocatedSimulators) {
    if ([simulator.name isEqualToString:deviceName]) {
      return simulator;
    }
  }
  return nil;
}

- (FBSimulator *)createSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration error:(NSError **)error
{
  NSString *targetName = [self targetNameForConfiguration:configuration];
  SimDeviceType *targetType = configuration.deviceType;
  SimRuntime *targetRuntime = configuration.runtime;

  NSError *innerError = nil;
  SimDevice *device = [self.deviceSet createDeviceWithType:targetType runtime:targetRuntime name:targetName error:&innerError];
  if (!device) {
    return [[[FBSimulatorError describeFormat:@"Failed to create a simulator with the name %@", targetName] causedBy:innerError] fail:error];
  }
  FBSimulator *simulator = [self inflateSimulatorFromSimDevice:device mustBeSelfManaged:YES];
  NSAssert(simulator, @"Expected simulator with name %@ to be inflatable", targetName);
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
    if ([self waitForDevice:simulator.device toChangeToState:FBSimulatorStateShutdown withError:&innerError]) {
      return YES;
    }

    // In Xcode 7 we can get stuck in the 'Creating' step as well, its possible that we can recover from this by erasing
    if (![self eraseSimulator:simulator withError:&innerError]) {
      return [[[[FBSimulatorError describe:@"Failed trying to prepare simulator for usage by erasing a stuck 'Creating' simulator %@"] causedBy:innerError] inSimulator:simulator] failBool:error];
    }

    // If a device has been erased, we should wait for it to actually be shutdown.
    if ([self waitForDevice:simulator.device toChangeToState:FBSimulatorStateShutdown withError:&innerError]) {
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
  if (![self waitForDevice:simulator.device toChangeToState:FBSimulatorStateShutdown withError:&innerError]) {
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
    @"E2E_%ld_%ld_%@_%@",
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
  for (FBSimulator *allocatedDevice in self.allocatedSimulators) {
    if (![allocatedDevice.device.deviceType isEqual:deviceType]) {
      continue;
    }
    if (![allocatedDevice.device.runtime isEqual:runtime]) {
      continue;
    }
    [indeces addIndex:allocatedDevice.offset];
  }
  for (NSInteger index = 0; index < INT_MAX; index++) {
    if (![indeces containsIndex:index]) {
      return index;
    }
  }
  return -1;
}

- (NSMutableOrderedSet *)inflatePooledSimulatorsMustBeManaged:(BOOL)mustBeOwnedByPool
{
  NSMutableOrderedSet *set = [NSMutableOrderedSet new];
  for (SimDevice *device in self.deviceSet.availableDevices) {
    FBSimulator *simulator = [self inflateSimulatorFromSimDevice:device mustBeSelfManaged:mustBeOwnedByPool];
    if (!simulator) {
      continue;
    }
    [set addObject:simulator];
  }
  [set sortUsingComparator:^NSComparisonResult(FBSimulator *left, FBSimulator *right) {
    return [left.name compare:right.name];
  }];

  return [set copy];
}

- (FBSimulator *)inflateSimulatorFromSimDevice:(SimDevice *)device mustBeSelfManaged:(BOOL)mustBeManaged
{
  FBSimulator *simulator = [self.class inflateSimulatorFromSimDevice:device];
  if (!simulator) {
    return nil;
  }
  if (simulator.bucketID == self.configuration.bucketID) {
    simulator.pool = self;
  }
  if (mustBeManaged && simulator.pool == nil) {
    return nil;
  }
  return simulator;
}

+ (FBSimulator *)inflateSimulatorFromSimDevice:(SimDevice *)device
{
  NSRegularExpression *regex = [self.class managedSimulatorPoolOffsetRegex];
  NSTextCheckingResult *result = [regex firstMatchInString:device.name options:0 range:NSMakeRange(0, device.name.length)];
  if (result.range.length == 0) {
    return nil;
  }

  NSInteger bucketID = [[device.name substringWithRange:[result rangeAtIndex:1]] integerValue];
  NSInteger offset = [[device.name substringWithRange:[result rangeAtIndex:2]] integerValue];

  FBSimulator *simulator = [FBSimulator new];
  simulator.device = device;
  simulator.bucketID = bucketID;
  simulator.offset = offset;
  return simulator;
}

+ (NSRegularExpression *)managedSimulatorPoolOffsetRegex
{
  static dispatch_once_t onceToken;
  static NSRegularExpression *regex;
  dispatch_once(&onceToken, ^{
    regex = [NSRegularExpression regularExpressionWithPattern:@"E2E_(\\d+)_(\\d+)" options:0 error:nil];
    NSCAssert(regex, @"Regex should compile");
  });
  return regex;
}

@end

@implementation FBSimulatorPool (Fetching)

- (NSString *)deviceUDIDWithName:(NSString *)deviceName simulatorSDK:(NSString *)simulatorSDK
{
  for (SimDevice *device in self.deviceSet.availableDevices) {
    if (![device.name isEqualToString:deviceName]) {
      continue;
    }
    if (!simulatorSDK) {
      return device.UDID.UUIDString;
    }
    if ([device.runtime.versionString isEqualToString:simulatorSDK]) {
      return device.UDID.UUIDString;
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

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

#import "FBSimulator+Private.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorConfiguration+DTMobile.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl+Private.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorInteraction.h"
#import "FBTaskExecutor.h"
#import "NSRunLoop+SimulatorControlAdditions.h"
#import "SimDevice.h"
#import "SimDeviceSet.h"
#import "SimDeviceType.h"
#import "SimRuntime.h"

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
  NSMutableOrderedSet *set = [NSMutableOrderedSet new];
  for (SimDevice *device in self.deviceSet.availableDevices) {
    FBSimulator *simulator = [self inflateSimulatorFromSimDevice:device];
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
  FBSimulator *device = [self findOrCreateDeviceWithConfiguration:configuration error:error];
  if (!device) {
    return nil;
  }
  if (![self prepareDeviceForUsage:device configuration:configuration error:error]) {
    return nil;
  }

  [self.allocatedWorkingSet addObject:device];
  return device;
}

- (BOOL)freeSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  [self.allocatedWorkingSet removeObject:simulator];

  NSError *innerError = nil;
  if (![self killManagedSimulators:@[simulator] withError:&innerError]) {
    return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to Free Device in Killing Device" errorOut:error];
  }

  // When 'deleting' on free, there's no point in erasing first
  BOOL deleteOnFree = (self.configuration.options & FBSimulatorManagementOptionsDeleteOnFree) == FBSimulatorManagementOptionsDeleteOnFree;
  if (deleteOnFree) {
    if (![self deleteManagedSimulator:simulator withError:&innerError]) {
      return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to Free Device in Deleting Device" errorOut:error];
    }
    return YES;
  }

  BOOL eraseOnFree = (self.configuration.options & FBSimulatorManagementOptionsEraseOnFree) == FBSimulatorManagementOptionsEraseOnFree;
  if (eraseOnFree) {
    if (![self eraseManagedSimulator:simulator withError:&innerError]) {
      return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to Free Device in Erasing Device" errorOut:error];
    }
    return YES;
  }

  return YES;
}

- (NSArray *)killManagedSimulatorsWithError:(NSError **)error
{
  return [self killManagedSimulators:self.allSimulatorsInPool.array withError:error];
}

- (NSArray *)killUnmanagedSimulatorsWithError:(NSError **)error
{
  // We want to blanket kill all the Simulator Binaries that aren't launched by us
  // this means that they don't contain -CurrentDeviceUDID.
  NSError *innerError = nil;
  if (![self blanketKillSimulatorAppsWithPidFilterPipe:@"grep -v CurrentDeviceUDID |" error:&innerError]) {
    return [FBSimulatorControl failWithError:innerError errorOut:error];
  }

  // This will make sure that the devices are killed themselves
  return [self shutdownDevices:self.unmanagedSimulators withError:error];
}

- (NSArray *)eraseManagedSimulatorsWithError:(NSError **)error
{
  NSError *innerError = nil;
  NSArray *simulators = [self.allSimulatorsInPool copy];

  // Kill all the simulators first
  if (![self killManagedSimulators:simulators withError:&innerError]) {
    return [FBSimulatorControl failWithError:innerError errorOut:error];
  }

  // Then erase.
  for (FBSimulator *simulator in simulators) {
    if (![self eraseManagedSimulator:simulator withError:&innerError]) {
      return [FBSimulatorControl failWithError:innerError errorOut:error];
    }
  }
  return simulators;
}

- (NSArray *)deleteManagedSimulatorsWithError:(NSError **)error
{
  NSError *innerError = nil;
  if (![self killManagedSimulatorsWithError:&innerError]) {
    return [FBSimulatorControl failWithError:innerError description:@"Failed to kill device before deleting it" errorOut:error];
  }

  NSMutableArray *deletedSimulatorNames = [NSMutableArray array];
  for (FBSimulator *simulator in self.allSimulatorsInPool) {
    if (![self.deviceSet deleteDevice:simulator.device error:&innerError]) {
      return [FBSimulatorControl failWithError:innerError description:@"Failed to delete device" errorOut:error];
    }
    [deletedSimulatorNames addObject:simulator.name];
  }
  return [deletedSimulatorNames copy];
}

#pragma mark - Private

- (BOOL)waitForDevice:(SimDevice *)device toChangeToState:(FBSimulatorState)simulatorState withError:(NSError **)error
{
  BOOL didChangeState = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:30 untilTrue:^ BOOL {
    return [FBSimulator simulatorStateFromStateString:device.stateString] == simulatorState;
  }];
  if (!didChangeState) {
    NSString *description = [NSString stringWithFormat:
      @"Simulator was not in expected %@ state, got %@",
      [FBSimulator stateStringFromSimulatorState:simulatorState],
      device.stateString
    ];
    return [FBSimulatorControl failBoolWithErrorMessage:description errorOut:error];
  }

  return YES;
}

- (BOOL)eraseManagedSimulator:(FBSimulator *)simulator withError:(NSError **)error
{
  NSError *innerError = nil;
  if (![simulator.device eraseContentsAndSettingsWithError:&innerError]) {
    NSString *description = [NSString stringWithFormat:@"Failed to Erase Contents and Settings %@", simulator];
    return [FBSimulatorControl failBoolWithError:innerError description:description errorOut:error];
  }
  return YES;
}

- (BOOL)deleteManagedSimulator:(FBSimulator *)simulator withError:(NSError **)error
{
  NSError *innerError = nil;
  if (![self.deviceSet deleteDevice:simulator.device error:&innerError]) {
    NSString *description = [NSString stringWithFormat:@"Failed to Delete simulator %@", simulator];
    return [FBSimulatorControl failBoolWithError:innerError description:description errorOut:error];
  }
  return YES;
}

- (NSArray *)killManagedSimulators:(NSArray *)simulators withError:(NSError **)error
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
  if (![self blanketKillSimulatorAppsWithPidFilterPipe:grepComponents error:&innerError]) {
    return [FBSimulatorControl failWithError:innerError errorOut:error];
  }

  NSArray *devices = [simulators valueForKey:@"device"];
  return [self shutdownDevices:devices withError:error];
}

- (NSArray *)shutdownDevices:(NSArray *)devices withError:(NSError **)error
{
  NSError *innerError = nil;
  for (SimDevice *device in devices) {
    if (![self safeShutdown:device withError:&innerError]) {
      return [FBSimulatorControl failWithError:innerError errorOut:error];
    }
  }
  return devices;
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
    return [FBSimulatorControl failBoolWithError:innerError description:@"Simulator could not be shutdown" errorOut:error];
  }

  // We rely on the catch-all-non-manged kill command to do the dirty work.
  // This will confirm that all these simulators are shutdown.
  return [self waitForDevice:device toChangeToState:FBSimulatorStateShutdown withError:error];
}

- (FBSimulator *)findOrCreateDeviceWithConfiguration:(FBSimulatorConfiguration *)configuration error:(NSError **)error
{
  SimDeviceType *targetType = configuration.deviceType;
  if (!targetType) {
    NSString *message = [NSString stringWithFormat:@"SimDeviceType for %@ does not exist", configuration];
    return [FBSimulatorControl failWithErrorMessage:message errorOut:error];
  }
  SimRuntime *targetRuntime = configuration.runtime;
  if (!targetRuntime) {
    NSString *message = [NSString stringWithFormat:@"SimRuntime for %@ does not exist", configuration];
    return [FBSimulatorControl failWithErrorMessage:message errorOut:error];
  }

  NSString *targetName = [NSString stringWithFormat:
    @"E2E_%ld_%ld_%@_%@",
    self.configuration.bucketID,
    [self nextAvailableOffsetForDeviceType:targetType runtime:targetRuntime],
    targetType.name,
    targetRuntime.versionString
  ];
  for (FBSimulator *simulator in self.unallocatedSimulators) {
    if (![simulator.name isEqualToString:targetName]) {
      continue;
    }
    return simulator;
  }

  NSError *innerError = nil;
  SimDevice *device = [self.deviceSet createDeviceWithType:targetType runtime:targetRuntime name:targetName error:&innerError];
  if (!device) {
    NSString *description = [NSString stringWithFormat:@"Failed to create a device with the name %@", targetName];
    return [FBSimulatorControl failWithError:innerError description:description errorOut:error];
  }
  FBSimulator *simulator = [self inflateSimulatorFromSimDevice:device];
  NSAssert(simulator, @"Expected simulator with name %@ to be inflatable", targetName);

  // Xcode 7 has a 'Creating' step that will potentially mess up steps further down the line
  // This additional step will confirim that everything is ok before we proceed.
  if (![self waitForDevice:device toChangeToState:FBSimulatorStateShutdown withError:&innerError]) {
    // In Xcode 7 we can get stuck in the 'Creating' step as well, its possible that we can recover from this by erasing
    if (![self eraseManagedSimulator:simulator withError:&innerError]) {
      NSString *description = [NSString stringWithFormat:@"Failed trying to create device, then erase it safely for %@", simulator];
      return [FBSimulatorControl failWithError:innerError description:description errorOut:error];
    }

    if (![self waitForDevice:device toChangeToState:FBSimulatorStateShutdown withError:&innerError]) {
      NSString *description = [NSString stringWithFormat:@"Failed trying to erase a created device, then wait for it to be shutdown: %@", simulator];
      return [FBSimulatorControl failWithError:innerError description:description errorOut:error];
    }
  }

  return simulator;
}

- (BOOL)prepareDeviceForUsage:(FBSimulator *)simulator configuration:(FBSimulatorConfiguration *)configuration error:(NSError **)error
{
  // If the device is in a strange state, we should bail now
  if (simulator.state == FBSimulatorStateUnknown) {
    return [FBSimulatorControl failBoolWithErrorMessage:@"Could not prepare device in an Unknown state" errorOut:error];
  }
  // If the device is being created, it doesn't need to be reset
  if (simulator.state == FBSimulatorStateCreating) {
    return YES;
  }

  // If the device is booted, we need to shut it down first.
  NSError *innerError = nil;
  if (simulator.state == FBSimulatorStateBooted) {
    if (![simulator.device shutdownWithError:&innerError]) {
      return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to shutdown device" errorOut:error];
    }
  }

  // Now we have a device that is shutdown, we should erase it
  if (![simulator.device eraseContentsAndSettingsWithError:&innerError]) {
    return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to erase device" errorOut:error];
  }

  // Do the other Simulator setup steps.
  if (![[[FBSimulatorInteraction withSimulator:simulator] configureWith:configuration] performInteractionWithError:&innerError]) {
    return [FBSimulatorControl failBoolWithError:innerError errorOut:error];
  }

  return YES;
}

#pragma mark - Helpers

#pragma mark Identifiers

- (BOOL)blanketKillSimulatorAppsWithPidFilterPipe:(NSString *)commandForPids error:(NSError **)error
{
  NSString *simulatorBinaryPath = self.configuration.simulatorApplication.binary.path;
  FBTaskExecutor *executor = FBTaskExecutor.sharedInstance;
  NSString *command = [NSString stringWithFormat:
    @"pgrep -lf %@ | %@ awk '{print $1}' | xargs kill",
    [FBTaskExecutor escapePathForShell:simulatorBinaryPath],
    commandForPids
  ];
  NSError *innerError = nil;
  if (![executor executeShellCommand:command returningError:&innerError]) {
    return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to Kill Simulator Process" errorOut:error];
  }
  return YES;
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

- (FBSimulator *)inflateSimulatorFromSimDevice:(SimDevice *)device
{
  NSRegularExpression *regex = [self.class managedSimulatorPoolOffsetRegex];
  NSTextCheckingResult *result = [regex firstMatchInString:device.name options:0 range:NSMakeRange(0, device.name.length)];
  if (result.range.length == 0) {
    return nil;
  }

  NSInteger bucketID = [[device.name substringWithRange:[result rangeAtIndex:1]] integerValue];
  if (bucketID != self.configuration.bucketID) {
    return nil;
  }
  NSInteger offset = [[device.name substringWithRange:[result rangeAtIndex:2]] integerValue];

  FBSimulator *simulator = [FBSimulator new];
  simulator.device = device;
  simulator.bucketID = bucketID;
  simulator.offset = offset;
  simulator.pool = self;
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
  [description appendFormat:@"SimDevice: %@", [self.deviceSet.availableDevices description]];
  [description appendFormat:@"\nAllocated Devices: %@", [self.allocatedSimulators description]];
  [description appendFormat:@"\nAll Managed Devices: %@", [self.allSimulatorsInPool description]];
  [description appendFormat:@"\nSimulator Proceesses: %@ \n\n", [self activeSimulatorProcessesWithError:nil]];
  return description;
}

- (NSString *)activeSimulatorProcessesWithError:(NSError *)error
{
  return [[[FBTaskExecutor.sharedInstance
    taskWithLaunchPath:@"/usr/bin/pgrep" arguments:@[@"-lf", @"Simulator"]]
    startSynchronouslyWithTimeout:8]
    stdOut];
}

@end

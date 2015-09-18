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
#import "FBSimulatorControl+Private.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
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
  if (![self killSimulators:@[simulator] withError:&innerError]) {
    return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to Free Device in Killing Device" errorOut:error];
  }

  // When 'deleting' on free, there's no point in erasing first
  BOOL deleteOnFree = (self.configuration.options & FBSimulatorManagementOptionsDeleteOnFree) == FBSimulatorManagementOptionsDeleteOnFree;
  if (deleteOnFree) {
    if (![self deleteSimulator:simulator withError:&innerError]) {
      return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to Free Device in Deleting Device" errorOut:error];
    }
    return YES;
  }

  BOOL eraseOnFree = (self.configuration.options & FBSimulatorManagementOptionsEraseOnFree) == FBSimulatorManagementOptionsEraseOnFree;
  if (eraseOnFree) {
    if (![self eraseSimulator:simulator withError:&innerError]) {
      return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to Free Device in Erasing Device" errorOut:error];
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
    return [FBSimulatorControl failWithError:innerError errorOut:error];
  }

  // We want to blanket kill all the Simulator Applications that belong to the current Xcode version
  // but aren't launched in the automated CurretnDeviceUDID way.
  if (![self blanketKillSimulatorAppsWithPidFilter:@"grep -v CurrentDeviceUDID |" error:&innerError]) {
    return [FBSimulatorControl failWithError:innerError errorOut:error];
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
    NSString *description = [NSString stringWithFormat:
      @"Simulator was not in expected %@ state, got %@",
      [FBSimulator stateStringFromSimulatorState:simulatorState],
      device.stateString
    ];
    return [FBSimulatorControl failBoolWithErrorMessage:description errorOut:error];
  }

  return YES;
}

- (BOOL)eraseSimulator:(FBSimulator *)simulator withError:(NSError **)error
{
  NSError *innerError = nil;
  if (![simulator.device eraseContentsAndSettingsWithError:&innerError]) {
    NSString *description = [NSString stringWithFormat:@"Failed to Erase Contents and Settings %@", simulator];
    return [FBSimulatorControl failBoolWithError:innerError description:description errorOut:error];
  }
  return YES;
}

- (BOOL)deleteSimulator:(FBSimulator *)simulator withError:(NSError **)error
{
  NSError *innerError = nil;
  if (![self.deviceSet deleteDevice:simulator.device error:&innerError]) {
    NSString *description = [NSString stringWithFormat:@"Failed to Delete simulator %@", simulator];
    return [FBSimulatorControl failBoolWithError:innerError description:description errorOut:error];
  }
  return YES;
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

- (NSArray *)deleteSimulators:(NSArray *)simulators withError:(NSError **)error
{
  NSError *innerError = nil;
  if (![self killSimulators:simulators withError:&innerError]) {
    return [FBSimulatorControl failWithError:innerError description:@"Failed to kill device before deleting it" errorOut:error];
  }

  NSMutableArray *deletedSimulatorNames = [NSMutableArray array];
  for (FBSimulator *simulator in simulators) {
    if (![self.deviceSet deleteDevice:simulator.device error:&innerError]) {
      return [FBSimulatorControl failWithError:innerError description:@"Failed to delete device" errorOut:error];
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
    return [FBSimulatorControl failWithError:innerError errorOut:error];
  }

  NSArray *devices = [simulators valueForKey:@"device"];
  return [self shutdownDevices:devices withError:error];
}

- (NSArray *)eraseSimulators:(NSArray *)simulators withError:(NSError **)error
{
  NSError *innerError = nil;
  // Kill all the simulators first
  if (![self killSimulators:simulators withError:&innerError]) {
    return [FBSimulatorControl failWithError:innerError errorOut:error];
  }

  // Then erase.
  for (FBSimulator *simulator in simulators) {
    if (![self eraseSimulator:simulator withError:&innerError]) {
      return [FBSimulatorControl failWithError:innerError errorOut:error];
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
  FBSimulator *simulator = [self inflateSimulatorFromSimDevice:device mustBeSelfManaged:YES];
  NSAssert(simulator, @"Expected simulator with name %@ to be inflatable", targetName);

  // Xcode 7 has a 'Creating' step that will potentially mess up steps further down the line
  // This additional step will confirim that everything is ok before we proceed.
  if (![self waitForDevice:device toChangeToState:FBSimulatorStateShutdown withError:&innerError]) {
    // In Xcode 7 we can get stuck in the 'Creating' step as well, its possible that we can recover from this by erasing
    if (![self eraseSimulator:simulator withError:&innerError]) {
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
  if (![[simulator.interact configureWith:configuration] performInteractionWithError:&innerError]) {
    return [FBSimulatorControl failBoolWithError:innerError errorOut:error];
  }

  return YES;
}

#pragma mark - Helpers

#pragma mark Identifiers

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
    return [FBSimulatorControl failBoolWithError:innerError description:@"Could not kill non-current xcode simulators" errorOut:error];
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
    NSString *description = [NSString stringWithFormat:@"Could not kill simulators with pid filter %@", pidFilter];
    return [FBSimulatorControl failBoolWithError:innerError description:description errorOut:error];
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

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorTerminationStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

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

@interface FBSimulatorTerminationStrategy ()

- (NSArray *)safeShutdownSimulators:(NSArray *)simulators withError:(NSError **)error;

@property (nonatomic, copy, readwrite) FBSimulatorControlConfiguration *configuration;
@property (nonatomic, copy, readwrite) NSArray *allSimulators;

@end

@interface FBSimulatorTerminationStrategy_PKill : FBSimulatorTerminationStrategy

@end

@implementation FBSimulatorTerminationStrategy_PKill

- (NSArray *)killAllWithError:(NSError **)error
{
  NSString *grepComponents = self.configuration.deviceSetPath
    // If the path of the DeviceSet exists we can kill Simulator.app processes that contain it in their launch.
    ? [NSString stringWithFormat:@"grep %@ |", self.configuration.deviceSetPath]
    // If there isn't a custom set path, we have to kill all simulators that contain a CurrentDeviceUDID launch
    : [NSString stringWithFormat:@"grep CurrentDeviceUDID | "];

  NSError *innerError = nil;
  if (![self blanketKillSimulatorAppsWithPidFilter:grepComponents error:&innerError]) {
    return [[[FBSimulatorError describe:@"Failed to kill all with DeviceSetPath"] causedBy:innerError] fail:error];
  }

  return [self safeShutdownSimulators:[self.allSimulators copy] withError:error];
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

  NSError *innerError = nil;
  if (![self blanketKillSimulatorAppsWithPidFilter:grepComponents error:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  return [self safeShutdownSimulators:simulators withError:error];
}

- (BOOL)killSpuriousSimulatorsWithError:(NSError **)error
{
  // We should also kill Simulators that are in totally the wrong Simulator binary.
  // Overlapping Xcode instances can't run on the same machine
  NSError *innerError = nil;
  if (![self blanketKillSimulatorsFromDifferentXcodeVersion:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  // We want to blanket kill all the Simulator Applications that belong to the current Xcode version
  // but aren't launched in the automated CurretnDeviceUDID way.
  if (![self blanketKillSimulatorAppsWithPidFilter:@"grep -v CurrentDeviceUDID |" error:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }
  return YES;
}

- (BOOL)blanketKillSimulatorsFromDifferentXcodeVersion:(NSError **)error
{
  // All Simulator Versions from Xcode 5-7, end in Simulator.app
  // This command kills all Simulator.app binaries that *don't* match the current Simulator Binary Path.
  NSString *simulatorBinaryPath = self.configuration.simulatorApplication.binary.path;
  NSString *command = [NSString stringWithFormat:
    @"pgrep -lf Simulator.app | grep -v %@ | awk '{print $1}'",
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

@end

@implementation FBSimulatorTerminationStrategy

+ (instancetype)usingKillOnConfiguration:(FBSimulatorControlConfiguration *)configuration allSimulators:(NSArray *)allSimulators
{
  return [[FBSimulatorTerminationStrategy_PKill alloc] initWithConfiguration:configuration allSimulators:allSimulators];
}

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration allSimulators:(NSArray *)allSimulators
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _allSimulators = allSimulators;
  return self;
}

- (NSArray *)killAllWithError:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSArray *)killSimulators:(NSArray *)simulators withError:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (BOOL)killSpuriousSimulatorsWithError:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

#pragma mark Private

- (NSArray *)safeShutdownSimulators:(NSArray *)simulators withError:(NSError **)error
{
  NSError *innerError = nil;
  for (FBSimulator *simulator in simulators) {
    if (![self safeShutdown:simulator withError:&innerError]) {
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
  return [simulator waitOnState:FBSimulatorStateShutdown withError:error];
}

@end

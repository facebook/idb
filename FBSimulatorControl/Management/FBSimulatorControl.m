/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControl.h"
#import "FBSimulatorControl+Private.h"

#import "FBProcessLaunchConfiguration.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSession+Convenience.h"
#import "FBSimulatorSession.h"
#import "FBSimulatorSessionState.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

#import <DVTiPhoneSimulatorRemoteClient/DTiPhoneSimulatorApplicationSpecifier.h>
#import <DVTiPhoneSimulatorRemoteClient/DTiPhoneSimulatorSession.h>
#import <DVTiPhoneSimulatorRemoteClient/DTiPhoneSimulatorSessionConfig.h>

#import <DVTFoundation/DVTPlatform.h>

@implementation FBSimulatorControl

#pragma mark - Initializers

+ (instancetype)sharedInstanceWithConfiguration:(FBSimulatorControlConfiguration *)configuration
{
  static dispatch_once_t onceToken;
  static FBSimulatorControl *simulatorControl;
  dispatch_once(&onceToken, ^{
    simulatorControl = [[self alloc] initWithConfiguration:configuration];
  });
  return simulatorControl;
}

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _simulatorPool = [FBSimulatorControl poolForConfiguration:configuration];
  return self;
}

- (void)dealloc
{
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - Public Methods

- (FBSimulatorSession *)createSessionForSimulatorConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration error:(NSError **)error;
{
  NSParameterAssert(simulatorConfiguration);

  NSError *innerError = nil;
  if (![self firstRunPreconditionsWithError:&innerError]) {
    return [FBSimulatorError failWithError:innerError description:@"Failed to meet first run preconditions" errorOut:error];
  }

  FBManagedSimulator *simulator = [self.simulatorPool
    allocateSimulatorWithConfiguration:simulatorConfiguration
    error:&innerError];

  if (!simulator) {
    return [FBSimulatorError failWithError:innerError description:@"Failed to allocate simulator" errorOut:error];
  }
  return [FBSimulatorSession sessionWithSimulator:simulator];
}

#pragma mark - Private Methods

- (BOOL)firstRunPreconditionsWithError:(NSError **)error
{
  if (self.hasRunOnce) {
    return YES;
  }

  NSError *innerError = nil;
  if (![DVTPlatform loadAllPlatformsReturningError:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError description:@"Failed to load DVTPlatform" errorOut:error];
  }

  if (self.configuration.deviceSetPath != nil) {
    if (![NSFileManager.defaultManager createDirectoryAtPath:self.configuration.deviceSetPath withIntermediateDirectories:YES attributes:nil error:&innerError]) {
      return [[[FBSimulatorError describeFormat:@"Failed to create custom SimDeviceSet directory at %@", self.configuration.deviceSetPath] causedBy:innerError] failBool:error];
    }
  }

  BOOL deleteOnStart = (self.configuration.options & FBSimulatorManagementOptionsDeleteManagedSimulatorsOnFirstStart) == FBSimulatorManagementOptionsDeleteManagedSimulatorsOnFirstStart;
  NSArray *result = deleteOnStart
    ? [self.simulatorPool deleteManagedSimulatorsWithError:&innerError]
    : [self.simulatorPool killManagedSimulatorsWithError:&innerError];

  if (!result) {
    return [FBSimulatorError failBoolWithError:innerError description:@"Failed to teardown previous simulators" errorOut:error];
  }

  BOOL killUnmanaged = (self.configuration.options & FBSimulatorManagementOptionsKillUnmanagedSimulatorsOnFirstStart) == FBSimulatorManagementOptionsKillUnmanagedSimulatorsOnFirstStart;
  if (killUnmanaged) {
    if (![self.simulatorPool killUnmanagedSimulatorsWithError:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError description:@"Failed to kill unmanaged simulators" errorOut:error];
    }
  }

  self.hasRunOnce = YES;
  return YES;
}

+ (FBSimulatorPool *)poolForConfiguration:(FBSimulatorControlConfiguration *)configuration
{
  return [FBSimulatorPool poolWithConfiguration:configuration deviceSet:[self deviceSetForConfiguration:configuration]];
}

+ (SimDeviceSet *)deviceSetForConfiguration:(FBSimulatorControlConfiguration *)configuration
{
  return configuration.deviceSetPath
    ? [SimDeviceSet setForSetPath:configuration.deviceSetPath]
    : SimDeviceSet.defaultSet;
}

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControl+Private.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

#import <DVTFoundation/DVTPlatform.h>

#import <DVTiPhoneSimulatorRemoteClient/DTiPhoneSimulatorApplicationSpecifier.h>
#import <DVTiPhoneSimulatorRemoteClient/DTiPhoneSimulatorSession.h>
#import <DVTiPhoneSimulatorRemoteClient/DTiPhoneSimulatorSessionConfig.h>

#import "FBProcessLaunchConfiguration.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl+Class.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSession+Convenience.h"
#import "FBSimulatorSession.h"
#import "FBSimulatorSessionState.h"

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

  FBSimulator *simulator = [self.simulatorPool
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

  BOOL killSpuriousCoreSimulatorServices = (self.configuration.options & FBSimulatorManagementOptionsKillSpuriousCoreSimulatorServices) == FBSimulatorManagementOptionsKillSpuriousCoreSimulatorServices;
  if (killSpuriousCoreSimulatorServices) {
    if (![self.simulatorPool.terminationStrategy killSpuriousCoreSimulatorServicesWithError:&innerError]) {
      return [[[FBSimulatorError describe:@"Failed to kill spurious CoreSimulatorServices"] causedBy:innerError] failBool:error];
    }
  }

  if (self.configuration.deviceSetPath != nil) {
    if (![NSFileManager.defaultManager createDirectoryAtPath:self.configuration.deviceSetPath withIntermediateDirectories:YES attributes:nil error:&innerError]) {
      return [[[FBSimulatorError describeFormat:@"Failed to create custom SimDeviceSet directory at %@", self.configuration.deviceSetPath] causedBy:innerError] failBool:error];
    }
  }

  BOOL deleteOnStart = (self.configuration.options & FBSimulatorManagementOptionsDeleteAllOnFirstStart) == FBSimulatorManagementOptionsDeleteAllOnFirstStart;
  NSArray *result = deleteOnStart
    ? [self.simulatorPool deleteAllWithError:&innerError]
    : [self.simulatorPool killAllWithError:&innerError];

  if (!result) {
    return [[[[FBSimulatorError describe:@"Failed to teardown previous simulators"] causedBy:innerError] recursiveDescription] failBool:error];
  }

  BOOL killSpuriousSimulators = (self.configuration.options & FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart) == FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart;
  if (killSpuriousSimulators) {
    BOOL failOnSpuriousKillFail = (self.configuration.options & FBSimulatorManagementOptionsIgnoreSpuriousKillFail) != FBSimulatorManagementOptionsIgnoreSpuriousKillFail;
    if (![self.simulatorPool.terminationStrategy killSpuriousSimulatorsWithError:&innerError] && failOnSpuriousKillFail) {
      return [[[[FBSimulatorError describe:@"Failed to kill spurious simulators"] causedBy:innerError] recursiveDescription] failBool:error];
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

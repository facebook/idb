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
#import "FBSimulatorPool.h"
#import "FBSimulatorSession+Convenience.h"
#import "FBSimulatorSession.h"
#import "FBSimulatorSessionState.h"

#import <DVTiPhoneSimulatorRemoteClient/DTiPhoneSimulatorApplicationSpecifier.h>
#import <DVTiPhoneSimulatorRemoteClient/DTiPhoneSimulatorSession.h>
#import <DVTiPhoneSimulatorRemoteClient/DTiPhoneSimulatorSessionConfig.h>

#import <DVTFoundation/DVTPlatform.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

NSString *const FBSimulatorControlErrorDomain = @"com.facebook.FBSimulatorControl";

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
  _simulatorPool = [FBSimulatorPool poolWithConfiguration:configuration deviceSet:SimDeviceSet.defaultSet];
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
    return [FBSimulatorControl failWithError:innerError description:@"Failed to meet first run preconditions" errorOut:error];
  }

  FBSimulator *simulator = [self.simulatorPool
    allocateSimulatorWithConfiguration:simulatorConfiguration
    error:&innerError];

  if (!simulator) {
    return [FBSimulatorControl failWithError:innerError description:@"Failed to allocate simulator" errorOut:error];
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
    return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to load DVTPlatform" errorOut:error];
  }

  BOOL deleteOnStart = (self.configuration.options & FBSimulatorManagementOptionsDeleteManagedSimulatorsOnFirstStart) == FBSimulatorManagementOptionsDeleteManagedSimulatorsOnFirstStart;
  NSArray *result = deleteOnStart
    ? [self.simulatorPool deleteManagedSimulatorsWithError:&innerError]
    : [self.simulatorPool killManagedSimulatorsWithError:&innerError];

  if (!result) {
    return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to teardown previous simulators" errorOut:error];
  }

  BOOL killUnmanaged = (self.configuration.options & FBSimulatorManagementOptionsKillUnmanagedSimulatorsOnFirstStart) == FBSimulatorManagementOptionsKillUnmanagedSimulatorsOnFirstStart;
  if (killUnmanaged) {
    if (![self.simulatorPool killUnmanagedSimulatorsWithError:&innerError]) {
      return [FBSimulatorControl failBoolWithError:innerError description:@"Failed to kill unmanaged simulators" errorOut:error];
    }
  }

  self.hasRunOnce = YES;
  return YES;
}

#pragma mark Errors

+ (NSError *)errorForDescription:(NSString *)description
{
  NSParameterAssert(description);
  return [NSError
    errorWithDomain:FBSimulatorControlErrorDomain
    code:0
    userInfo:@{NSLocalizedDescriptionKey : description}];
}

+ (id)failWithErrorMessage:(NSString *)errorMessage errorOut:(NSError **)errorOut
{
  NSParameterAssert(errorMessage);
  if (errorOut) {
    *errorOut = [NSError
      errorWithDomain:FBSimulatorControlErrorDomain
      code:0
      userInfo:@{ NSLocalizedDescriptionKey : errorMessage}];
  }
  return nil;
}

+ (id)failWithError:(NSError *)failureCause errorOut:(NSError **)errorOut
{
  NSParameterAssert(failureCause);
  if (errorOut) {
    *errorOut = failureCause;
  }
  return nil;
}

+ (id)failWithError:(NSError *)failureCause description:(NSString *)description errorOut:(NSError **)errorOut
{
  NSParameterAssert(failureCause);
  NSParameterAssert(description);
  if (!errorOut) {
    return nil;
  }
  *errorOut = [NSError
    errorWithDomain:FBSimulatorControlErrorDomain
    code:0
    userInfo:@{ NSUnderlyingErrorKey : failureCause, NSLocalizedDescriptionKey : description }];
  return nil;
}

+ (BOOL)failBoolWithErrorMessage:(NSString *)errorMessage errorOut:(NSError **)errorOut
{
  return [self failBoolWithError:[self errorForDescription:errorMessage] errorOut:errorOut];
}

+ (BOOL)failBoolWithError:(NSError *)failureCause errorOut:(NSError **)errorOut
{
  NSParameterAssert(failureCause);
  if (errorOut) {
    *errorOut = failureCause;
  }
  return NO;
}

+ (BOOL)failBoolWithError:(NSError *)failureCause description:(NSString *)description errorOut:(NSError **)errorOut
{
  NSParameterAssert(failureCause);
  NSParameterAssert(description);
  if (!errorOut) {
    return NO;
  }
  *errorOut = [NSError
    errorWithDomain:FBSimulatorControlErrorDomain
    code:0
    userInfo:@{ NSUnderlyingErrorKey : failureCause, NSLocalizedDescriptionKey : description }];
  return NO;
}

@end

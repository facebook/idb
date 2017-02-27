/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSettingsCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBDefaultsModificationStrategy.h"

@interface FBSimulatorSettingsCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorSettingsCommands

+ (instancetype)commandWithSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  return self;
}

- (BOOL)overridingLocalization:(FBLocalizationOverride *)localizationOverride error:(NSError **)error
{
  if (!localizationOverride) {
    return YES;
  }

  return [[FBLocalizationDefaultsModificationStrategy
    strategyWithSimulator:self.simulator]
    overrideLocalization:localizationOverride error:error];
}

- (BOOL)authorizeLocationSettings:(NSArray<NSString *> *)bundleIDs error:(NSError **)error
{
  return [[FBLocationServicesModificationStrategy
    strategyWithSimulator:self.simulator]
    approveLocationServicesForBundleIDs:bundleIDs error:error];
}

- (BOOL)authorizeLocationSettingForApplication:(FBApplicationDescriptor *)application error:(NSError **)error
{
  NSParameterAssert(application);
  return [self authorizeLocationSettings:@[application.bundleID] error:error];
}

- (BOOL)overrideWatchDogTimerForApplications:(NSArray<NSString *> *)bundleIDs withTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return [[FBWatchdogOverrideModificationStrategy
    strategyWithSimulator:self.simulator]
    overrideWatchDogTimerForApplications:bundleIDs timeout:timeout error:error];
}

- (BOOL)setupKeyboardWithError:(NSError **)error
{
  return [[FBKeyboardSettingsModificationStrategy
    strategyWithSimulator:self.simulator]
    setupKeyboardWithError:error];
}

@end

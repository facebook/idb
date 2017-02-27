/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Settings.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBDefaultsModificationStrategy.h"

@implementation FBSimulatorInteraction (Settings)

- (instancetype)overridingLocalization:(FBLocalizationOverride *)localizationOverride
{
  if (!localizationOverride) {
    return [self succeed];
  }

  return [self interactWithShutdownSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBLocalizationDefaultsModificationStrategy
      strategyWithSimulator:simulator]
      overrideLocalization:localizationOverride error:error];
  }];
}

- (instancetype)authorizeLocationSettings:(NSArray<NSString *> *)bundleIDs
{
  return [self interactWithSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBLocationServicesModificationStrategy
      strategyWithSimulator:simulator]
      approveLocationServicesForBundleIDs:bundleIDs error:error];
  }];
}

- (instancetype)authorizeLocationSettingForApplication:(FBApplicationDescriptor *)application
{
  NSParameterAssert(application);
  return [self authorizeLocationSettings:@[application.bundleID]];
}

- (instancetype)overrideWatchDogTimerForApplications:(NSArray<NSString *> *)bundleIDs withTimeout:(NSTimeInterval)timeout
{
  return [self interactWithSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBWatchdogOverrideModificationStrategy
      strategyWithSimulator:simulator]
      overrideWatchDogTimerForApplications:bundleIDs timeout:timeout error:error];
  }];
}

- (instancetype)setupKeyboard
{
  return [self interactWithSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBKeyboardSettingsModificationStrategy
      strategyWithSimulator:simulator]
      setupKeyboardWithError:error];
  }];
}

@end

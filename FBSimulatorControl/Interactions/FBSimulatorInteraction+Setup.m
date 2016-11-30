/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Setup.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBPlistModificationStrategy.h"

@implementation FBSimulatorInteraction (Setup)

- (instancetype)prepareForBoot:(FBSimulatorBootConfiguration *)configuration
{
  return [[self
    overridingLocalization:configuration.localizationOverride]
    setupKeyboard];
}

- (instancetype)overridingLocalization:(FBLocalizationOverride *)localizationOverride
{
  if (!localizationOverride) {
    return [self succeed];
  }

  return [self interactWithShutdownSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBPlistModificationStrategy strategyWithSimulator:simulator]
      amendRelativeToPath:@"Library/Preferences/.GlobalPreferences.plist"
      error:error
      amendWithBlock:^(NSMutableDictionary *dictionary) {
        [dictionary addEntriesFromDictionary:localizationOverride.defaultsDictionary];
      }];
  }];
}

- (instancetype)authorizeLocationSettings:(NSArray<NSString *> *)bundleIDs
{
  NSParameterAssert(bundleIDs);

  return [self interactWithShutdownSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBPlistModificationStrategy strategyWithSimulator:simulator]
      amendRelativeToPath:@"Library/Caches/locationd/clients.plist"
      error:error
      amendWithBlock:^(NSMutableDictionary *dictionary) {
        for (NSString *bundleID in bundleIDs) {
          dictionary[bundleID] = @{
            @"Whitelisted": @NO,
            @"BundleId": bundleID,
            @"SupportedAuthorizationMask" : @3,
            @"Authorization" : @2,
            @"Authorized": @YES,
            @"Executable": @"",
            @"Registered": @"",
          };
        }
      }];
  }];
}

- (instancetype)authorizeLocationSettingForApplication:(FBApplicationDescriptor *)application
{
  NSParameterAssert(application);
  return [self authorizeLocationSettings:@[application.bundleID]];
}

- (instancetype)overrideWatchDogTimerForApplications:(NSArray<NSString *> *)bundleIDs withTimeout:(NSTimeInterval)timeout
{
  NSParameterAssert(bundleIDs);
  NSParameterAssert(timeout);

  return [self interactWithShutdownSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBPlistModificationStrategy strategyWithSimulator:simulator]
      amendRelativeToPath:@"Library/Preferences/com.apple.springboard.plist"
      error:error
      amendWithBlock:^(NSMutableDictionary *dictionary) {
        NSMutableDictionary *exceptions = [NSMutableDictionary dictionary];
        for (NSString *bundleID in bundleIDs) {
          exceptions[bundleID] = @(timeout);
        }
        dictionary[@"FBLaunchWatchdogExceptions"] = exceptions;
      }];
  }];
}

- (instancetype)setupKeyboard
{
  return [self
      editPropertyListFileRelativeFromRootPath:@"Library/Preferences/com.apple.Preferences.plist"
      amendWithBlock:^(NSMutableDictionary *dictionary) {
        dictionary[@"KeyboardCapsLock"] = @NO;
        dictionary[@"KeyboardAutocapitalization"] = @NO;
        dictionary[@"KeyboardAutocorrection"] = @NO;
      }];
}

- (instancetype)editPropertyListFileRelativeFromRootPath:(NSString *)relativePath amendWithBlock:( void(^)(NSMutableDictionary *) )block
{
  return [self interactWithShutdownSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBPlistModificationStrategy strategyWithSimulator:simulator]
      amendRelativeToPath:relativePath
      error:error
      amendWithBlock:block];
  }];
}

@end

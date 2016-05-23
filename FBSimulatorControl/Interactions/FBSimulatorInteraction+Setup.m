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

#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorLaunchConfiguration.h"

@implementation FBSimulatorInteraction (Setup)

- (instancetype)prepareForLaunch:(FBSimulatorLaunchConfiguration *)configuration
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
    return [FBSimulatorInteraction
      forSimulator:simulator
      relativeFromRootPath:@"Library/Preferences/.GlobalPreferences.plist"
      error:error
      amendWithBlock:^(NSMutableDictionary *dictionary) {
        [dictionary addEntriesFromDictionary:localizationOverride.defaultsDictionary];
      }];
  }];
}

- (instancetype)authorizeLocationSettings:(NSArray *)bundleIDs
{
  NSParameterAssert(bundleIDs);

  return [self interactWithShutdownSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [FBSimulatorInteraction
      forSimulator:simulator
      relativeFromRootPath:@"Library/Caches/locationd/clients.plist"
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

- (instancetype)authorizeLocationSettingForApplication:(FBSimulatorApplication *)application
{
  NSParameterAssert(application);
  return [self authorizeLocationSettings:@[application.bundleID]];
}

- (instancetype)overrideWatchDogTimerForApplications:(NSArray *)bundleIDs withTimeout:(NSTimeInterval)timeout
{
  NSParameterAssert(bundleIDs);
  NSParameterAssert(timeout);

  return [self interactWithShutdownSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [FBSimulatorInteraction
      forSimulator:simulator
      relativeFromRootPath:@"Library/Preferences/com.apple.springboard.plist"
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
  return [self interactWithShutdownSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [FBSimulatorInteraction
      forSimulator:simulator
      relativeFromRootPath:@"Library/Preferences/com.apple.Preferences.plist"
      error:error
      amendWithBlock:^(NSMutableDictionary *dictionary) {
        dictionary[@"KeyboardCapsLock"] = @NO;
        dictionary[@"KeyboardAutocapitalization"] = @NO;
        dictionary[@"KeyboardAutocorrection"] = @NO;
      }];
  }];
}

#pragma mark Private

+ (BOOL)forSimulator:(FBSimulator *)simulator relativeFromRootPath:(NSString *)relativePath error:(NSError **)error amendWithBlock:( void(^)(NSMutableDictionary *) )block
{
  NSString *simulatorRoot = simulator.device.dataPath;
  NSString *path = [simulatorRoot stringByAppendingPathComponent:relativePath];

  NSError *innerError = nil;
  if (![NSFileManager.defaultManager createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&innerError]) {
    return [[[[FBSimulatorError
      describeFormat:@"Could not create intermediate directories for plist modification at %@", path]
      inSimulator:simulator]
      causedBy:innerError]
      failBool:error];
  }
  NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
  block(dictionary);

  if (![dictionary writeToFile:path atomically:YES]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to write plist at path %@", path]
      inSimulator:simulator]
      failBool:error];
  }
  return YES;
}

@end

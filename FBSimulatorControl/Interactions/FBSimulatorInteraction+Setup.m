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

#import "FBInteraction+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorLaunchConfiguration.h"

@implementation FBSimulatorInteraction (Setup)

- (instancetype)prepareForLaunch:(FBSimulatorLaunchConfiguration *)configuration
{
  return [[self
    setLocale:configuration.locale]
    setupKeyboard];
}

- (instancetype)setLocale:(NSLocale *)locale
{
  if (!locale) {
    return [self succeed];
  }

  return [self interactWithShutdownSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    NSString *localeIdentifier = [locale localeIdentifier];
    NSString *languageIdentifier = [NSLocale canonicalLanguageIdentifierFromString:localeIdentifier];
    NSDictionary *preferencesDict = @{
      @"AppleLocale": localeIdentifier,
      @"AppleLanguages": @[ languageIdentifier ],
      // We force the simulator to have a US keyboard for automation's sake.
      @"AppleKeyboards": @[ @"en_US@hw=US;sw=QWERTY" ],
      @"AppleKeyboardsExpanded": @1,
    };

    NSString *simulatorRoot = simulator.device.dataPath;
    NSString *path = [simulatorRoot stringByAppendingPathComponent:@"Library/Preferences/.GlobalPreferences.plist"];
    if (![preferencesDict writeToFile:path atomically:YES]) {
      return [FBSimulatorError failBoolWithError:nil description:@"Failed to write .GlobalPreferences.plist" errorOut:error];
    }

    return YES;
  }];
}

- (instancetype)authorizeLocationSettings:(NSArray *)bundleIDs
{
  NSParameterAssert(bundleIDs);

  return [self interactWithShutdownSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    NSString *simulatorRoot = simulator.device.dataPath;

    NSString *locationClientsDirectory = [simulatorRoot stringByAppendingPathComponent:@"Library/Caches/locationd"];
    NSError *innerError = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:locationClientsDirectory withIntermediateDirectories:YES attributes:nil error:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError description:@"Failed to create locationd" errorOut:error];
    }

    NSString *locationClientsPath = [locationClientsDirectory stringByAppendingPathComponent:@"clients.plist"];
    NSMutableDictionary *locationClients = [NSMutableDictionary dictionaryWithContentsOfFile:locationClientsPath] ?: [NSMutableDictionary dictionary];
    for (NSString *bundleID in bundleIDs) {
      locationClients[bundleID] = @{
        @"Whitelisted": @NO,
        @"BundleId": bundleID,
        @"SupportedAuthorizationMask" : @3,
        @"Authorization" : @2,
        @"Authorized": @YES,
        @"Executable": @"",
        @"Registered": @"",
      };
    }

    if (![locationClients writeToFile:locationClientsPath atomically:YES]) {
      return [FBSimulatorError failBoolWithError:innerError description:@"Failed to write clients.plist" errorOut:error];
    }
    return YES;
  }];
}

- (instancetype)authorizeLocationSettingForApplication:(FBSimulatorApplication *)application
{
  NSParameterAssert(application);
  return [self authorizeLocationSettings:@[application.bundleID]];
}

- (instancetype)setupKeyboard
{
  return [self interactWithShutdownSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    NSString *simulatorRoot = simulator.device.dataPath;
    NSString *preferencesPath = [simulatorRoot stringByAppendingPathComponent:@"Library/Preferences/com.apple.Preferences.plist"];
    NSError *innerError = nil;
    NSMutableDictionary *preferences = [NSMutableDictionary dictionaryWithContentsOfFile:preferencesPath] ?: [NSMutableDictionary dictionary];
    preferences[@"KeyboardCapsLock"] = @NO;
    preferences[@"KeyboardAutocapitalization"] = @NO;
    preferences[@"KeyboardAutocorrection"] = @NO;
    if (![preferences writeToFile:preferencesPath atomically:YES]) {
      return [FBSimulatorError failBoolWithError:innerError description:@"Failed to write com.apple.Preferences.plist" errorOut:error];
    }
    return YES;
  }];
}

@end

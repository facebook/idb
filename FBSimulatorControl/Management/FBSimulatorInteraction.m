/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction.h"
#import "FBSimulatorInteraction+Private.h"

#import <CoreSimulator/SimDevice.h>

#import "FBInteraction+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorError.h"

@implementation FBSimulatorInteraction

+ (instancetype)withSimulator:(FBSimulator *)simulator
{
  FBSimulatorInteraction *interaction = [self new];
  interaction.simulator = simulator;
  return interaction;
}

- (instancetype)setLocale:(NSLocale *)locale
{
  NSParameterAssert(locale);

  FBSimulator *simulator = self.simulator;

  return [self interact:^ BOOL (NSError **error, id _) {
    NSString *localeIdentifier = [locale localeIdentifier];
    NSString *languageIdentifier = [NSLocale canonicalLanguageIdentifierFromString:localeIdentifier];
    NSDictionary *preferencesDict = @{
      @"AppleLocale": localeIdentifier,
      @"AppleLanguages": @[ languageIdentifier ],
    };

    NSString *simulatorRoot = simulator.device.dataPath;
    NSString *path = [simulatorRoot stringByAppendingPathComponent:@"Library/Preferences/.GlobalPreferences.plist"];
    if (![preferencesDict writeToFile:path atomically:YES]) {
      return [FBSimulatorError failBoolWithError:nil description:@"Failed to write .GlobalPreferences.plist" errorOut:error];
    }

    return YES;
  }];
}

- (instancetype)authorizeLocationSettingsForApplication:(FBSimulatorApplication *)application
{
  NSParameterAssert(application);

  FBSimulator *simulator = self.simulator;

  return [self interact:^ BOOL (NSError **error, id _) {
    NSString *simulatorRoot = simulator.device.dataPath;
    NSString *bundleID = application.bundleID;

    NSString *locationClientsDirectory = [simulatorRoot stringByAppendingPathComponent:@"Library/Caches/locationd"];
    NSError *innerError = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:locationClientsDirectory withIntermediateDirectories:YES attributes:nil error:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError description:@"Failed to create locationd" errorOut:error];
    }

    NSString *locationClientsPath = [locationClientsDirectory stringByAppendingPathComponent:@"clients.plist"];
    NSMutableDictionary *locationClients = [NSMutableDictionary dictionaryWithContentsOfFile:locationClientsPath] ?: [NSMutableDictionary dictionary];
    locationClients[bundleID] = @{
      @"Whitelisted": @NO,
      @"BundleId": bundleID,
      @"SupportedAuthorizationMask" : @3,
      @"Authorization" : @2,
      @"Authorized": @YES,
      @"Executable": @"",
      @"Registered": @"",
    };

    if (![locationClients writeToFile:locationClientsPath atomically:YES]) {
      return [FBSimulatorError failBoolWithError:innerError description:@"Failed to write clients.plist" errorOut:error];
    }
    return YES;
  }];
}


- (instancetype)setupKeyboard
{
  FBSimulator *simulator = self.simulator;

  return [self interact:^ BOOL (NSError **error, id _) {
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

@implementation FBSimulatorInteraction (Convenience)

- (instancetype)configureWith:(FBSimulatorConfiguration *)configuration
{
  if (configuration.locale) {
    [self setLocale:configuration.locale];
  }
  return [self setupKeyboard];
}

@end

@implementation FBSimulator (FBSimulatorInteraction)

- (FBSimulatorInteraction *)interact
{
  return [FBSimulatorInteraction withSimulator:self];
}

@end

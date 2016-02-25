/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControl+PrincipalClass.h"

#import <AppKit/AppKit.h>

#import <CoreSimulator/NSUserDefaults-SimDefaults.h>
#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import <DVTFoundation/DVTPlatform.h>

#import "FBCollectionDescriptions.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorControlGlobalConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorHistory.h"
#import "FBSimulatorLogger.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSet.h"

@implementation FBSimulatorControl

#pragma mark Initializers

+ (void)initialize
{
  [FBSimulatorControl loadPrivateFrameworksOrAbort];
}

+ (instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration error:(NSError **)error
{
  return [self withConfiguration:configuration logger:FBSimulatorControlGlobalConfiguration.defaultLogger error:error];
}

+ (instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration logger:(id<FBSimulatorLogger>)logger error:(NSError **)error
{
  return [[FBSimulatorControl alloc] initWithConfiguration:configuration logger:logger error:error];
}

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration logger:(id<FBSimulatorLogger>)logger error:(NSError **)error
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = [FBSimulatorSet setWithConfiguration:configuration control:self logger:logger error:error];
  if (!_set) {
    return nil;
  }
  _configuration = configuration;
  _pool = [FBSimulatorPool poolWithSet:_set logger:logger];

  return self;
}

#pragma mark Framework Loading

+ (BOOL)loadPrivateFrameworks:(id<FBSimulatorLogger>)logger error:(NSError **)error
{
  static BOOL hasLoaded = NO;
  if (hasLoaded) {
    return YES;
  }

  // This will assert if the directory could not be found.
  NSString *developerDirectory = FBSimulatorControlGlobalConfiguration.developerDirectory;

  // A Mapping of Class Names to the Frameworks that they belong to. This serves to:
  // 1) Represent the Frameworks that FBSimulatorControl is dependent on via their classes
  // 2) Provide a path to the relevant Framework.
  // 3) Provide a class for sanity checking the Framework load.
  // 4) Provide a class that can be checked before the Framework load to avoid re-loading the same
  //    Framework if others have done so before.
  // 5) Provide a sanity check that any preloaded Private Frameworks match the current xcode-select version
  NSDictionary *classMapping = @{
    @"SimDevice" : @"Library/PrivateFrameworks/CoreSimulator.framework",
    @"SimDeviceFramebufferService" : @"Library/PrivateFrameworks/SimulatorKit.framework",
    @"DVTDevice" : @"../SharedFrameworks/DVTFoundation.framework",
    @"DTiPhoneSimulatorApplicationSpecifier" : @"../SharedFrameworks/DVTiPhoneSimulatorRemoteClient.framework"
  };
  [logger logFormat:@"Using Developer Directory %@", developerDirectory];

  for (NSString *className in classMapping) {
    NSString *relativePath = classMapping[className];
    NSString *path = [[developerDirectory stringByAppendingPathComponent:relativePath] stringByStandardizingPath];

    // The Class exists, therefore has been loaded
    if (NSClassFromString(className)) {
      [logger logFormat:@"%@ is already loaded, skipping load of framework %@", className, path];
      NSError *innerError = nil;
      if (![self verifyDeveloperDirectoryForPrivateClass:className developerDirectory:developerDirectory logger:logger error:&innerError]) {
        return [FBSimulatorError failBoolWithError:innerError errorOut:error];
      }
      continue;
    }

    // Otherwise load the Framework.
    [logger logFormat:@"%@ is not loaded. Loading %@ at path %@", className, path.lastPathComponent, path];
    NSError *innerError = nil;
    if (![self loadFrameworkAtPath:path logger:logger error:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }
    [logger logFormat:@"Loaded %@ from %@", className, path];
  }

  // We're done with loading Frameworks.
  hasLoaded = YES;
  [logger logFormat:@"Loaded All Private Frameworks %@", [FBCollectionDescriptions oneLineDescriptionFromArray:classMapping.allValues atKeyPath:@"lastPathComponent"]];

  // Set CoreSimulator Logging since it is now loaded.
  [self setCoreSimulatorLoggingEnabled:FBSimulatorControlGlobalConfiguration.debugLoggingEnabled];

  return YES;
}

+ (void)loadPrivateFrameworksOrAbort
{
  id<FBSimulatorLogger> logger = FBSimulatorControlGlobalConfiguration.defaultLogger;
  NSError *error = nil;
  BOOL success = [FBSimulatorControl loadPrivateFrameworks:logger.debug error:&error];
  if (success) {
    return;
  }
  [logger.error logFormat:@"Failed to load Frameworks with error %@", error];
  abort();
}

#pragma mark Private Methods

+ (void)setCoreSimulatorLoggingEnabled:(BOOL)enabled
{
  NSUserDefaults *simulatorDefaults = [NSUserDefaults simulatorDefaults];
  [simulatorDefaults setBool:enabled forKey:@"DebugLogging"];
}

+ (BOOL)loadFrameworkAtPath:(NSString *)path logger:(id<FBSimulatorLogger>)logger error:(NSError **)error
{
  NSBundle *bundle = [NSBundle bundleWithPath:path];
  if (!bundle) {
    return [[FBSimulatorError
      describeFormat:@"Failed to load the bundle for path %@", path]
      failBool:error];
  }

  NSError *innerError = nil;
  if (![bundle loadAndReturnError:&innerError]) {
    return [[FBSimulatorError
      describeFormat:@"Failed to load the the Framework Bundle %@", bundle]
      failBool:error];
  }
  [logger logFormat:@"Successfully loaded %@", path.lastPathComponent];
  return YES;
}

/**
 Given that it is possible for FBSimulatorControl.framework to be loaded after any of the
 Private Frameworks upon which it depends, it's possible that these Frameworks may have
 been loaded from a different Developer Directory.

 In order to prevent crazy behaviour from arising, FBSimulatorControl will check the
 directories of these Frameworks match the one that is currently set.
 */
+ (BOOL)verifyDeveloperDirectoryForPrivateClass:(NSString *)className developerDirectory:(NSString *)developerDirectory logger:(id<FBSimulatorLogger>)logger error:(NSError **)error
{
  NSBundle *bundle = [NSBundle bundleForClass:NSClassFromString(className)];
  if (!bundle) {
    return [[FBSimulatorError
      describeFormat:@"Could not obtain Framework bundle for class named %@", className]
      failBool:error];
  }

  // Developer Directory is: /Applications/Xcode.app/Contents/Developer
  // The common base path is: is: /Applications/Xcode.app
  NSString *basePath = [[developerDirectory stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
  if (![bundle.bundlePath hasPrefix:basePath]) {
    return [[FBSimulatorError
      describeFormat:@"Expected Framework %@ to be loaded for Developer Directory at path %@, but was loaded from %@", bundle.bundlePath.lastPathComponent, bundle.bundlePath, developerDirectory]
      failBool:error];
  }
  [logger logFormat:@"%@ has correct path of %@", className, basePath];
  return YES;
}

@end

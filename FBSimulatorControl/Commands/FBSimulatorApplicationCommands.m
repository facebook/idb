/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorApplicationCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBApplicationLaunchStrategy.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorLaunchCtl.h"
#import "FBSimulatorProcessFetcher.h"
#import "FBSimulatorSubprocessTerminationStrategy.h"

@interface FBSimulatorApplicationCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorApplicationCommands

+ (instancetype)commandsWithSimulator:(FBSimulator *)simulator
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

#pragma mark - FBApplicationCommands Implementation

- (BOOL)installApplicationWithPath:(NSString *)path error:(NSError **)error
{
  NSURL *tempDirURL = nil;

  NSString *appPath = [FBApplicationDescriptor findOrExtractApplicationAtPath:path extractPathOut:&tempDirURL error:error];
  if (appPath == nil) {
    return NO;
  }

  BOOL installResult = [self installExtractedApplicationWithPath:appPath error:error];
  if (tempDirURL != nil) {
    [NSFileManager.defaultManager removeItemAtURL:tempDirURL error:nil];
  }
  return installResult;
}

- (BOOL)uninstallApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSParameterAssert(bundleID);

  // Confirm the app is suitable to be uninstalled.
  if ([self.simulator isSystemApplicationWithBundleID:bundleID error:nil]) {
    return [[[FBSimulatorError
      describeFormat:@"Can't uninstall '%@' as it is a system Application", bundleID]
      inSimulator:self.simulator]
      failBool:error];
  }
  NSError *innerError = nil;
  if (![self.simulator installedApplicationWithBundleID:bundleID error:&innerError]) {
    return [[[[FBSimulatorError
      describeFormat:@"Can't uninstall '%@' as it isn't installed", bundleID]
      causedBy:innerError]
      inSimulator:self.simulator]
      failBool:error];
  }
  // Kill the app if it's running
  [self killApplicationWithBundleID:bundleID error:nil];
  // Then uninstall for real.
  if (![self.simulator.device uninstallApplication:bundleID withOptions:nil error:&innerError]) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to uninstall '%@'", bundleID]
      causedBy:innerError]
      inSimulator:self.simulator]
      failBool:error];
  }
  return YES;
}

- (BOOL)isApplicationInstalledWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return [self.simulator installedApplicationWithBundleID:bundleID error:error] != nil;
}

- (BOOL)launchApplication:(FBApplicationLaunchConfiguration *)configuration error:(NSError **)error
{
  return [[FBApplicationLaunchStrategy strategyWithSimulator:self.simulator] launchApplication:configuration error:error] != nil;
}

- (BOOL)killApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSError *innerError = nil;
  FBProcessInfo *process = [self.simulator runningApplicationWithBundleID:bundleID error:&innerError];
  if (!process) {
    return [[[[FBSimulatorError
      describeFormat:@"Could not find a running application for '%@'", bundleID]
      inSimulator:self.simulator]
      causedBy:innerError]
      failBool:error];
  }
  if (![[FBSimulatorSubprocessTerminationStrategy strategyWithSimulator:self.simulator] terminate:process error:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  return YES;
}

- (NSArray<FBApplicationDescriptor *> *)installedApplications
{
  NSMutableArray<FBApplicationDescriptor *> *applications = [NSMutableArray array];
  for (NSDictionary *appInfo in [[self.simulator.device installedAppsWithError:nil] allValues]) {
    FBApplicationDescriptor *application = [FBApplicationDescriptor applicationWithPath:appInfo[ApplicationPathKey] installTypeString:appInfo[ApplicationTypeKey] error:nil];
    if (!application) {
      continue;
    }
    [applications addObject:application];
  }
  return [applications copy];
}

- (BOOL)installExtractedApplicationWithPath:(NSString *)path error:(NSError **)error
{
  NSError *innerError = nil;

  FBApplicationDescriptor *application = [FBApplicationDescriptor userApplicationWithPath:path error:&innerError];
  if (!application) {
    return [[[FBSimulatorError
      describeFormat:@"Could not determine Application information for path %@", path]
      causedBy:innerError]
      failBool:error];
  }

  if ([self.simulator isSystemApplicationWithBundleID:application.bundleID error:nil]) {
    return YES;
  }

  NSSet<NSString *> *binaryArchitectures = application.binary.architectures;
  NSSet<NSString *> *supportedArchitectures = FBControlCoreConfigurationVariants.baseArchToCompatibleArch[self.simulator.deviceType.simulatorArchitecture];
  if (![binaryArchitectures intersectsSet:supportedArchitectures]) {
    return [[FBSimulatorError
      describeFormat:
        @"Simulator does not support any of the architectures (%@) of the executable at %@. Simulator Archs (%@)",
        [FBCollectionInformation oneLineDescriptionFromArray:binaryArchitectures.allObjects],
        application.binary.path,
        [FBCollectionInformation oneLineDescriptionFromArray:supportedArchitectures.allObjects]]
      failBool:error];
  }

  NSDictionary *options = @{
    @"CFBundleIdentifier" : application.bundleID
  };
  NSURL *appURL = [NSURL fileURLWithPath:application.path];

  if (![self.simulator.device installApplication:appURL withOptions:options error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to install Application %@ with options %@", application, options]
      causedBy:innerError]
      failBool:error];
  }

  return YES;
}

#pragma mark - FBSimulatorApplicationCommands

#pragma mark Launching / Terminating Applications

- (BOOL)launchOrRelaunchApplication:(FBApplicationLaunchConfiguration *)appLaunch error:(NSError **)error
{
  NSParameterAssert(appLaunch);
  return [[FBApplicationLaunchStrategy
    strategyWithSimulator:self.simulator]
    launchOrRelaunchApplication:appLaunch error:error];
}

- (BOOL)terminateApplication:(FBApplicationDescriptor *)application error:(NSError **)error
{
  NSParameterAssert(application);
  return [self killApplicationWithBundleID:application.bundleID error:error];
}

- (BOOL)relaunchLastLaunchedApplicationWithError:(NSError **)error
{
  return [[FBApplicationLaunchStrategy
    strategyWithSimulator:self.simulator]
    relaunchLastLaunchedApplicationWithError:error];
}

- (BOOL)terminateLastLaunchedApplicationWithError:(NSError **)error
{
  return [[FBApplicationLaunchStrategy
    strategyWithSimulator:self.simulator]
    terminateLastLaunchedApplicationWithError:error];
}

#pragma mark Querying Application State

- (nullable FBApplicationDescriptor *)installedApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSParameterAssert(bundleID);

  NSError *innerError = nil;
  NSDictionary *appInfo = [self appInfo:bundleID error:&innerError];
  if (!appInfo) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  NSString *appPath = appInfo[ApplicationPathKey];
  NSString *typeString = appInfo[ApplicationTypeKey];
  FBApplicationDescriptor *application = [FBApplicationDescriptor applicationWithPath:appPath installTypeString:typeString error:&innerError];
  if (!application) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to get App Path of %@ at %@", bundleID, appPath]
      inSimulator:self.simulator]
      causedBy:innerError]
      fail:error];
  }
  return application;
}

- (BOOL)isSystemApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSParameterAssert(bundleID);

  NSError *innerError = nil;
  NSDictionary *appInfo = [self appInfo:bundleID error:&innerError];
  if (!appInfo) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  return [appInfo[ApplicationTypeKey] isEqualToString:@"System"];
}

- (nullable NSString *)homeDirectoryOfApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSParameterAssert(bundleID);

  // It appears that the release notes for Xcode 8.3 Beta 2 aren't correct in referencing rdar://30224453
  // "The simctl get_app_container command can now return the path of an app's data container or App Group containers"
  // It doesn't appear that simctl currently supports this, it will only show the Installed path of an Application.
  // This means it won't show it's "Container" Jail.
  // It appears that the API for getting this location is only provided on the Simulator side in MobileCoreServices.framework
  // There is a call to a function called container_create_or_lookup_path_for_current_user, which allows the HOME environment variable
  // to be set for any Application. This is likely the true path to the Application Container, not where the .app is installed.
  NSError *innerError = nil;
  FBProcessInfo *runningApplication = [self runningApplicationWithBundleID:bundleID error:&innerError];
  if (!runningApplication) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  NSString *homeDirectory = runningApplication.environment[@"HOME"];
  if (![NSFileManager.defaultManager fileExistsAtPath:homeDirectory]) {
    return [[FBSimulatorError describeFormat:@"App Home Directory does not exist at path %@", homeDirectory] fail:error];
  }

  return homeDirectory;
}

- (nullable FBProcessInfo *)runningApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSParameterAssert(bundleID);

  NSError *innerError = nil;
  FBApplicationDescriptor *application = [self installedApplicationWithBundleID:bundleID error:&innerError];
  if (!application) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  pid_t processIdentifier = 0;
  if (![self.simulator.launchctl serviceNameForBundleID:bundleID processIdentifierOut:&processIdentifier error:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  FBProcessInfo *processInfo = [self.simulator.processFetcher.processFetcher processInfoFor:processIdentifier];
  if (!processInfo) {
    return [[FBSimulatorError
      describeFormat:@"Could not fetch process info for %@ %d", processInfo, processIdentifier]
      fail:error];
  }
  return processInfo;
}

#pragma mark Private

- (nullable NSDictionary<NSString *, id> *)appInfo:(NSString *)bundleID error:(NSError **)error
{
  NSError *innerError = nil;
  NSDictionary *appInfo = [self.simulator.device propertiesOfApplication:bundleID error:&innerError];
  if (!appInfo) {
    NSDictionary *installedApps = [self.simulator.device installedAppsWithError:nil];
    return [[[[[FBSimulatorError
      describeFormat:@"Application with bundle ID '%@' is not installed", bundleID]
      extraInfo:@"installed_apps" value:installedApps.allKeys]
      inSimulator:self.simulator]
      causedBy:innerError]
      fail:error];
  }
  return appInfo;
}

@end

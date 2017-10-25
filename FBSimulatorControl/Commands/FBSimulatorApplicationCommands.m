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
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorLaunchCtlCommands.h"
#import "FBSimulatorProcessFetcher.h"
#import "FBSimulatorSubprocessTerminationStrategy.h"

@interface FBSimulatorApplicationCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorApplicationCommands

+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  return [[self alloc] initWithSimulator:target];
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

- (FBFuture<NSNull *> *)installApplicationWithPath:(NSString *)path
{
  return [[[FBApplicationBundle
    onQueue:self.simulator.asyncQueue findOrExtractApplicationAtPath:path]
    onQueue:self.simulator.workQueue fmap:^FBFuture *(FBExtractedApplication *extractedApplication) {
      return [[self installExtractedApplicationWithPath:extractedApplication.bundle.path] mapReplace:extractedApplication];
    }]
    onQueue:self.simulator.asyncQueue notifyOfCompletion:^(FBFuture<FBExtractedApplication *> *future) {
      if (future.result.extractedPath) {
        [NSFileManager.defaultManager removeItemAtURL:future.result.extractedPath error:nil];
      }
    }];
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

- (FBFuture<NSArray<FBInstalledApplication *> *> *)installedApplications
{
  NSMutableArray<FBInstalledApplication *> *applications = [NSMutableArray array];
  for (NSDictionary *appInfo in [[self.simulator.device installedAppsWithError:nil] allValues]) {
    FBInstalledApplication *application = [FBSimulatorApplicationCommands installedApplicationFromInfo:appInfo error:nil];
    if (!application) {
      continue;
    }
    [applications addObject:application];
  }
  return [FBFuture futureWithResult:[applications copy]];
}

#pragma mark - FBSimulatorApplicationCommands

#pragma mark Application Lifecycle

- (FBFuture<NSNull *> *)uninstallApplicationWithBundleID:(NSString *)bundleID
{
  NSParameterAssert(bundleID);

  // Confirm the app is suitable to be uninstalled.
  if ([self.simulator isSystemApplicationWithBundleID:bundleID error:nil]) {
    return [[[FBSimulatorError
      describeFormat:@"Can't uninstall '%@' as it is a system Application", bundleID]
      inSimulator:self.simulator]
      failFuture];
  }
  NSError *innerError = nil;
  if (![self.simulator installedApplicationWithBundleID:bundleID error:&innerError]) {
    return [[[[FBSimulatorError
      describeFormat:@"Can't uninstall '%@' as it isn't installed", bundleID]
      causedBy:innerError]
      inSimulator:self.simulator]
      failFuture];
  }
  // Kill the app if it's running
  [self killApplicationWithBundleID:bundleID error:nil];
  // Then uninstall for real.
  if (![self.simulator.device uninstallApplication:bundleID withOptions:nil error:&innerError]) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to uninstall '%@'", bundleID]
      causedBy:innerError]
      inSimulator:self.simulator]
      failFuture];
  }
  return [FBFuture futureWithResult:NSNull.null];
}

- (BOOL)launchOrRelaunchApplication:(FBApplicationLaunchConfiguration *)appLaunch error:(NSError **)error
{
  NSParameterAssert(appLaunch);
  return [[FBApplicationLaunchStrategy
    strategyWithSimulator:self.simulator]
    launchOrRelaunchApplication:appLaunch error:error] != nil;
}

#pragma mark Querying Application State

- (nullable FBInstalledApplication *)installedApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSParameterAssert(bundleID);

  NSDictionary *appInfo = [self.simulator.device propertiesOfApplication:bundleID error:error];
  if (!appInfo) {
    return nil;
  }
  return [FBSimulatorApplicationCommands installedApplicationFromInfo:appInfo error:error];
}

- (BOOL)isSystemApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  FBInstalledApplication *application = [self installedApplicationWithBundleID:bundleID error:error];
  if (!application) {
    return NO;
  }

  return application.installType == FBApplicationInstallTypeSystem;
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
  FBInstalledApplication *application = [self installedApplicationWithBundleID:bundleID error:&innerError];
  if (!application) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  pid_t processIdentifier = 0;
  if (![self.simulator serviceNameForBundleID:bundleID processIdentifierOut:&processIdentifier error:&innerError]) {
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

static NSString *const KeyDataContainer = @"DataContainer";

+ (FBInstalledApplication *)installedApplicationFromInfo:(NSDictionary<NSString *, id> *)appInfo error:(NSError **)error
{
  NSString *appName = appInfo[FBApplicationInstallInfoKeyBundleName];
  if (![appName isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"Bundle Name %@ is not a String for %@ in %@", appName, FBApplicationInstallInfoKeyBundleName, appInfo]
      fail:error];
  }
  NSString *bundleIdentifier = appInfo[FBApplicationInstallInfoKeyBundleIdentifier];
  if (![bundleIdentifier isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"Bundle Identifier %@ is not a String for %@ in %@", bundleIdentifier, FBApplicationInstallInfoKeyBundleIdentifier, appInfo]
      fail:error];
  }
  NSString *appPath = appInfo[FBApplicationInstallInfoKeyPath];
  if (![appPath isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"App Path %@ is not a String for %@ in %@", appPath, FBApplicationInstallInfoKeyPath, appInfo]
      fail:error];
  }
  NSString *typeString = appInfo[FBApplicationInstallInfoKeyApplicationType];
  if (![typeString isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"Install Type %@ is not a String for %@ in %@", typeString, FBApplicationInstallInfoKeyApplicationType, appInfo]
      fail:error];
  }
  NSURL *dataContainer = appInfo[KeyDataContainer];
  if (dataContainer && ![dataContainer isKindOfClass:NSURL.class]) {
    return [[FBControlCoreError
      describeFormat:@"Data Container %@ is not a NSURL for %@ in %@", dataContainer, KeyDataContainer, appInfo]
      fail:error];
  }

  FBApplicationBundle *bundle = [FBApplicationBundle applicationWithPath:appPath error:error];
  if (!bundle) {
    return nil;
  }

  return [FBInstalledApplication
    installedApplicationWithBundle:bundle
    installType:[FBInstalledApplication installTypeFromString:typeString]
    dataContainer:dataContainer.path];
}

- (FBFuture<NSNull *> *)installExtractedApplicationWithPath:(NSString *)path
{
  NSError *error = nil;
  FBApplicationBundle *application = [FBApplicationBundle applicationWithPath:path error:&error];
  if (!application) {
    return [[[FBSimulatorError
      describeFormat:@"Could not determine Application information for path %@", path]
      causedBy:error]
      failFuture];
  }

  if ([self.simulator isSystemApplicationWithBundleID:application.bundleID error:&error]) {
    return [FBFuture futureWithError:error];
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
      failFuture];
  }

  NSDictionary *options = @{
    @"CFBundleIdentifier" : application.bundleID
  };
  NSURL *appURL = [NSURL fileURLWithPath:application.path];

  if (![self.simulator.device installApplication:appURL withOptions:options error:&error]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to install Application %@ with options %@", application, options]
      causedBy:error]
      failFuture];
  }

  return [FBFuture futureWithResult:NSNull.null];
}

@end

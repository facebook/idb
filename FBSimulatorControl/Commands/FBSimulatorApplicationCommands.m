/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorApplicationCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulatorApplicationLaunchStrategy.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorApplicationOperation.h"
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
  return [[[FBBundleDescriptor
    onQueue:self.simulator.asyncQueue findOrExtractApplicationAtPath:path logger:self.simulator.logger]
    onQueue:self.simulator.workQueue pop:^(FBBundleDescriptor *bundle) {
      return [self installExtractedApplicationWithPath:bundle.path];
    }]
    mapReplace:NSNull.null];
}

- (FBFuture<NSNumber *> *)isApplicationInstalledWithBundleID:(NSString *)bundleID
{
  return [[self.simulator
    installedApplicationWithBundleID:bundleID]
    onQueue:self.simulator.asyncQueue chain:^FBFuture *(FBFuture *future) {
      return [FBFuture futureWithResult:@(future.result != nil)];
    }];
}

- (FBFuture<FBSimulatorApplicationOperation *> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration
{
  return [[FBSimulatorApplicationLaunchStrategy
    strategyWithSimulator:self.simulator]
    launchApplication:configuration];
}

- (FBFuture<NSNull *> *)killApplicationWithBundleID:(NSString *)bundleID
{
  if (!bundleID) {
    return [[FBSimulatorError describe:@"Bundle ID was not provided"] failFuture];
  }
  return [[FBSimulatorSubprocessTerminationStrategy strategyWithSimulator:self.simulator] terminateApplication:bundleID];
}

- (FBFuture<NSArray<FBInstalledApplication *> *> *)installedApplications
{
  return [[FBFuture
    resolveValue:^ NSDictionary<NSString *, id> * (NSError **error) {
      return [self.simulator.device installedAppsWithError:error];
    }]
    onQueue:self.simulator.asyncQueue map:^(NSDictionary<NSString *, id> *installedApps) {
      NSMutableArray<FBInstalledApplication *> *applications = [NSMutableArray array];
      for (NSDictionary *appInfo in installedApps.allValues) {
        FBInstalledApplication *application = [FBSimulatorApplicationCommands installedApplicationFromInfo:appInfo error:nil];
        if (!application) {
          continue;
        }
        [applications addObject:application];
      }
      return applications;
    }];
}

#pragma mark - FBSimulatorApplicationCommands

#pragma mark Application Lifecycle

- (FBFuture<NSNull *> *)uninstallApplicationWithBundleID:(NSString *)bundleID
{
  NSParameterAssert(bundleID);

  return [[[[self.simulator
    installedApplicationWithBundleID:bundleID]
    onQueue:self.simulator.asyncQueue fmap:^FBFuture *(FBInstalledApplication *installedApplication) {
      if (installedApplication.installType == FBApplicationInstallTypeSystem) {
        return [[FBSimulatorError
          describeFormat:@"Can't uninstall '%@' as it is a system Application", installedApplication]
          failFuture];
      }
      return [FBFuture futureWithResult:installedApplication];
    }]
    onQueue:self.simulator.workQueue fmap:^(FBInstalledApplication *_) {
      return [[self.simulator killApplicationWithBundleID:bundleID] fallback:NSNull.null];
    }]
    onQueue:self.simulator.workQueue fmap:^ FBFuture<NSNull *> * (id _) {
      NSError *error = nil;
      if (![self.simulator.device uninstallApplication:bundleID withOptions:nil error:&error]) {
        return [[[FBSimulatorError
          describeFormat:@"Failed to uninstall '%@'", bundleID]
          causedBy:error]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

#pragma mark Querying Application State

- (FBFuture<FBInstalledApplication *> *)installedApplicationWithBundleID:(NSString *)bundleID
{
  NSParameterAssert(bundleID);

  NSError *error = nil;
  // appInfo is usually always returned, even if there is no app installed.
  NSDictionary *appInfo = [self.simulator.device propertiesOfApplication:bundleID error:&error];
  if (!appInfo) {
    return [FBFuture futureWithError:error];
  }
  // Therefore we have to parse the app info to see that it is actually a real app.
  FBInstalledApplication *application = [FBSimulatorApplicationCommands installedApplicationFromInfo:appInfo error:&error];
  if (!application) {
    return [[FBSimulatorError
      describeFormat:@"Application Info %@ could not be parsed (it's probably not installed): %@", [FBCollectionInformation oneLineDescriptionFromDictionary:appInfo], error]
      failFuture];
  }
  return [FBFuture futureWithResult:application];
}

- (FBFuture<NSDictionary<NSString *, NSNumber *> *> *)runningApplications
{
  return [[self.simulator
    serviceNamesAndProcessIdentifiersForSubstring:@"UIKitApplication"]
    onQueue:self.simulator.asyncQueue map:^(NSDictionary<NSString *, NSNumber *> *serviceNameToProcessIdentifier) {
      NSMutableDictionary<NSString *, NSNumber *> *mapping = [NSMutableDictionary dictionary];
      for (NSString *serviceName in serviceNameToProcessIdentifier.allKeys) {
        NSString *bundleName = [FBSimulatorLaunchCtlCommands extractApplicationBundleIdentifierFromServiceName:serviceName];
        if (!bundleName) {
          continue;
        }
        mapping[bundleName] = serviceNameToProcessIdentifier[serviceName];
      }
      return mapping;
    }];
}

- (FBFuture<FBProcessInfo *> *)runningApplicationWithBundleID:(NSString *)bundleID
{
  NSParameterAssert(bundleID);
  return [[[self
    installedApplicationWithBundleID:bundleID]
    onQueue:self.simulator.workQueue fmap:^(FBInstalledApplication *_) {
      NSString *serviceName = [NSString stringWithFormat:@"UIKitApplication:%@", bundleID];
      return [self.simulator serviceNameAndProcessIdentifierForSubstring:serviceName];
    }]
    onQueue:self.simulator.workQueue fmap:^(NSArray<id> *result) {
      NSNumber *processIdentifier = result[1];
      FBProcessInfo *processInfo = [self.simulator.processFetcher.processFetcher processInfoFor:processIdentifier.intValue];
      if (!processInfo) {
        return [[FBSimulatorError
          describeFormat:@"Could not fetch process info for %@", processIdentifier]
          failFuture];
      }
      return [FBFuture futureWithResult:processInfo];
    }];
}

- (FBFuture<NSNumber *> *)processIDWithBundleID:(NSString *)bundleID
{
  return [[self
    runningApplicationWithBundleID:bundleID]
    onQueue:self.simulator.workQueue map:^(FBProcessInfo *info) {
      return @(info.processIdentifier);
    }];
}

#pragma mark Private

static NSString *const KeyDataContainer = @"DataContainer";

+ (FBInstalledApplication *)installedApplicationFromInfo:(NSDictionary<NSString *, id> *)appInfo error:(NSError **)error
{
  NSString *appName = appInfo[FBApplicationInstallInfoKeyBundleName];
  if (![appName isKindOfClass:NSString.class]) {
    return [[[FBControlCoreError
      describeFormat:@"Bundle Name %@ is not a String for %@ in %@", appName, FBApplicationInstallInfoKeyBundleName, appInfo]
      noLogging]
      fail:error];
  }
  NSString *bundleIdentifier = appInfo[FBApplicationInstallInfoKeyBundleIdentifier];
  if (![bundleIdentifier isKindOfClass:NSString.class]) {
    return [[[FBControlCoreError
      describeFormat:@"Bundle Identifier %@ is not a String for %@ in %@", bundleIdentifier, FBApplicationInstallInfoKeyBundleIdentifier, appInfo]
      noLogging]
      fail:error];
  }
  NSString *appPath = appInfo[FBApplicationInstallInfoKeyPath];
  if (![appPath isKindOfClass:NSString.class]) {
    return [[[FBControlCoreError
      describeFormat:@"App Path %@ is not a String for %@ in %@", appPath, FBApplicationInstallInfoKeyPath, appInfo]
      noLogging]
      fail:error];
  }
  NSString *typeString = appInfo[FBApplicationInstallInfoKeyApplicationType];
  if (![typeString isKindOfClass:NSString.class]) {
    return [[[FBControlCoreError
      describeFormat:@"Install Type %@ is not a String for %@ in %@", typeString, FBApplicationInstallInfoKeyApplicationType, appInfo]
      noLogging]
      fail:error];
  }
  NSURL *dataContainer = appInfo[KeyDataContainer];
  if (dataContainer && ![dataContainer isKindOfClass:NSURL.class]) {
    return [[[FBControlCoreError
      describeFormat:@"Data Container %@ is not a NSURL for %@ in %@", dataContainer, KeyDataContainer, appInfo]
      noLogging]
      fail:error];
  }

  FBBundleDescriptor *bundle = [FBBundleDescriptor bundleFromPath:appPath error:error];
  if (!bundle) {
    return nil;
  }

  return [FBInstalledApplication
    installedApplicationWithBundle:bundle
    installType:[FBInstalledApplication installTypeFromString:typeString signerIdentity:nil]
    dataContainer:dataContainer.path];
}

- (FBFuture<NSNull *> *)installExtractedApplicationWithPath:(NSString *)path
{
  return [[self
    confirmCompatibilityOfApplicationAtPath:path]
    onQueue:self.simulator.workQueue fmap:^FBFuture *(FBBundleDescriptor *application) {
      NSDictionary *options = @{
        @"CFBundleIdentifier": application.identifier
      };
      NSURL *appURL = [NSURL fileURLWithPath:application.path];

      NSError *error = nil;
      if ([self.simulator.device installApplication:appURL withOptions:options error:&error]) {
        return FBFuture.empty;
      }

      // Retry install if the first attempt failed with 'Failed to load Info.plist...'.
      // This is to mitagate an error where the first install of an app after uninstalling it
      // always fails.
      // See Apple bug report 46691107
      if ([error.description containsString:@"Failed to load Info.plist from bundle at path"]) {
        [self.simulator.logger log:@"Retrying install due to reinstall bug"];
        error = nil;
        if ([self.simulator.device installApplication:appURL withOptions:options error:&error]) {
          return FBFuture.empty;
        }
      }

      return [[[FBSimulatorError
        describeFormat:@"Failed to install Application %@ with options %@", application, options]
        causedBy:error]
        failFuture];
    }];
}

- (FBFuture<FBBundleDescriptor *> *)confirmCompatibilityOfApplicationAtPath:(NSString *)path
{
  NSError *error = nil;
  FBBundleDescriptor *application = [FBBundleDescriptor bundleFromPath:path error:&error];
  if (!application) {
    return [[[FBSimulatorError
      describeFormat:@"Could not determine Application information for path %@", path]
      causedBy:error]
      failFuture];
  }

  return [[self.simulator
    installedApplicationWithBundleID:application.identifier]
    onQueue:self.simulator.workQueue chain:^FBFuture *(FBFuture<FBInstalledApplication *> *future) {
      FBInstalledApplication *installed = future.result;
      if (installed && installed.installType == FBApplicationInstallTypeSystem) {
        return [[FBSimulatorError
         describeFormat:@"Cannot install app as it is a system app %@", installed]
         failFuture];
      }
      NSSet<NSString *> *binaryArchitectures = application.binary.architectures;
      NSSet<NSString *> *supportedArchitectures = FBiOSTargetConfiguration.baseArchToCompatibleArch[self.simulator.deviceType.simulatorArchitecture];
      if (![binaryArchitectures intersectsSet:supportedArchitectures]) {
        return [[FBSimulatorError
          describeFormat:
            @"Simulator does not support any of the architectures (%@) of the executable at %@. Simulator Archs (%@)",
            [FBCollectionInformation oneLineDescriptionFromArray:binaryArchitectures.allObjects],
            application.binary.path,
            [FBCollectionInformation oneLineDescriptionFromArray:supportedArchitectures.allObjects]]
          failFuture];
      }
      return [FBFuture futureWithResult:application];
    }];
}

@end

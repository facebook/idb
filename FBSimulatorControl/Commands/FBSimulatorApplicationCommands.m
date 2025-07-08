/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorApplicationCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorLaunchCtlCommands.h"
#import "FBSimulatorLaunchedApplication.h"
#import "FBSimulatorProcessSpawnCommands.h"

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

- (FBFuture<FBInstalledApplication *> *)installApplicationWithPath:(NSString *)path
{
  return [[self
    confirmCompatibilityOfApplicationAtPath:path]
    onQueue:self.simulator.workQueue fmap:^ FBFuture<FBInstalledApplication *> * (FBBundleDescriptor *appBundle) {
      NSDictionary *options = @{
        @"CFBundleIdentifier": appBundle.identifier
      };
      NSURL *appURL = [NSURL fileURLWithPath:appBundle.path];
      NSError *error = nil;
      if ([self.simulator.device installApplication:appURL withOptions:options error:&error]) {
        return [self installedApplicationWithBundleID:appBundle.identifier];
      }

      // Retry install if the first attempt failed with 'Failed to load Info.plist...'.
      // This is to mitagate an error where the first install of an app after uninstalling it
      // always fails.
      // See Apple bug report 46691107
      if ([error.description containsString:@"Failed to load Info.plist from bundle at path"]) {
        [self.simulator.logger log:@"Retrying install due to reinstall bug"];
        error = nil;
        if ([self.simulator.device installApplication:appURL withOptions:options error:&error]) {
          return [self installedApplicationWithBundleID:appBundle.identifier];
        }
      }

      return [[[FBSimulatorError
        describeFormat:@"Failed to install Application %@ with options %@", appBundle, options]
        causedBy:error]
        failFuture];
    }];
}

- (FBFuture<FBSimulatorLaunchedApplication *> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration
{
  FBSimulator *simulator = self.simulator;
  FBProcessIO *io = configuration.io;
  return [[[FBFuture futureWithFutures:@[
      [self ensureApplicationIsInstalled:configuration.bundleID],
      [self confirmApplicationLaunchState:configuration.bundleID launchMode:configuration.launchMode waitForDebugger:configuration.waitForDebugger],
    ]]
    onQueue:simulator.workQueue fmap:^(id _) {
      return [io attachViaFile];
    }]
    onQueue:simulator.workQueue fmap:^ FBFuture<FBSimulatorLaunchedApplication *> * (FBProcessFileAttachment *attachment) {
      FBFuture<NSNumber *> *launch = [self launchApplication:configuration stdOut:attachment.stdOut stdErr:attachment.stdErr];
      return [FBSimulatorLaunchedApplication applicationWithSimulator:simulator configuration:configuration attachment:attachment launchFuture:launch];
    }];
}

- (FBFuture<NSNull *> *)killApplicationWithBundleID:(NSString *)bundleID
{
  if (!bundleID) {
    return [[FBSimulatorError
      describe:@"Bundle ID was not provided"]
      failFuture];
  }
  SimDevice *simDevice = self.simulator.device;
  return [FBFuture
    onQueue:self.simulator.workQueue resolveValue:^ NSNull * (NSError **error) {
      if (![simDevice terminateApplicationWithID:bundleID error:error]) {
        return nil;
      }
      return NSNull.null;
    }];
}

- (FBFuture<NSArray<FBInstalledApplication *> *> *)installedApplications
{
  return [[FBFuture
    onQueue:self.simulator.workQueue resolveValue:^ NSDictionary<NSString *, id> * (NSError **error) {
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

- (FBFuture<FBInstalledApplication *> *)installedApplicationWithBundleID:(NSString *)bundleID
{
  return [FBFuture
    onQueue:self.simulator.workQueue resolveValue:^ FBInstalledApplication * (NSError **error) {
      return [self installedApplicationWithBundleID:bundleID error:error];
    }];
}

- (FBFuture<NSDictionary<NSString *, NSNumber *> *> *)runningApplications
{
  static dispatch_once_t onceToken;
  static NSRegularExpression *regex;
  dispatch_once(&onceToken, ^{
    NSError *error = nil;
    regex = [NSRegularExpression regularExpressionWithPattern:@"UIKitApplication:" options:0 error:&error];
    NSCAssert(error == nil, @"Invalid regular expression");
  });


  return [[self.simulator
    serviceNamesAndProcessIdentifiersMatching:regex]
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

- (FBFuture<NSNumber *> *)processIDWithBundleID:(NSString *)bundleID
{
  NSError *error = nil;
  NSString *pattern = [NSString stringWithFormat:@"UIKitApplication:%@(\\[|$)",[NSRegularExpression escapedPatternForString:bundleID]];
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
  if (error) {
    return [[FBSimulatorError
             describeFormat:@"Couldn't build search pattern for '%@'", bundleID]
             failFuture];
  }
  return [[FBFuture
    onQueue:self.simulator.workQueue resolve:^{
      return [self.simulator firstServiceNameAndProcessIdentifierMatching:regex];
    }]
    onQueue:self.simulator.workQueue map:^(NSArray<id> *result) {
      return result[1];
    }];
}

#pragma mark - FBSimulatorApplicationCommands

- (FBInstalledApplication *)installedApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error;
{
  // -[SimDevice propertiesOfApplication:error:] will return in success if the app could not be found.
  // The dictionary only contains one element, which is the bundle id of the non-existant app.
  // This internal helper method understands this, so we can just re-use it here.
  SimDevice *device = self.simulator.device;
  NSString *applicationType = nil;
  BOOL applicationIsInstalled = [device applicationIsInstalled:bundleID type:&applicationType error:error];
  if (!applicationIsInstalled) {
    return [[FBSimulatorError
      describeFormat:@"Cannot get app information for '%@', it is not installed", bundleID]
      fail:error];
  }
  // appInfo is usually always returned, even if there is no app installed.
  NSDictionary<NSString *, id> *appInfo = [device propertiesOfApplication:bundleID error:error];
  if (!appInfo) {
    return nil;
  }
  // Therefore we have to parse the app info to see that it is actually a real app.
  FBInstalledApplication *application = [FBSimulatorApplicationCommands installedApplicationFromInfo:appInfo error:error];
  if (!application) {
    return nil;
  }
  return application;
}

#pragma mark Private

- (FBFuture<NSNumber *> *)ensureApplicationIsInstalled:(NSString *)bundleID
{
  return [[[self.simulator
    installedApplicationWithBundleID:bundleID]
    mapReplace:NSNull.null]
    onQueue:self.simulator.asyncQueue handleError:^(NSError *error) {
      return [[FBSimulatorError
        describeFormat:@"App %@ can't be launched as it isn't installed: %@", bundleID, error]
        failFuture];
    }];
}

- (FBFuture<NSNumber *> *)confirmApplicationLaunchState:(NSString *)bundleID launchMode:(FBApplicationLaunchMode)launchMode waitForDebugger:(BOOL)waitForDebugger
{
  if (waitForDebugger && launchMode == FBApplicationLaunchModeForegroundIfRunning) {
    return [[FBSimulatorError
      describe:@"'Foreground if running' and 'wait for debugger cannot be applied simultaneously"]
      failFuture];
  }

  FBSimulator *simulator = self.simulator;
  return [[simulator
    processIDWithBundleID:bundleID]
    onQueue:simulator.asyncQueue chain:^ FBFuture<NSNull *> * (FBFuture<NSNumber *> *processFuture) {
      NSNumber *processID = processFuture.result;
      if (!processID) {
        return FBFuture.empty;
      }
      if (launchMode == FBApplicationLaunchModeFailIfRunning) {
        return [[FBSimulatorError
          describeFormat:@"App %@ can't be launched as is running (PID=%@)", bundleID, processID]
          failFuture];
      } else if (launchMode == FBApplicationLaunchModeRelaunchIfRunning) {
        return [self killApplicationWithBundleID:bundleID];
      }
      return FBFuture.empty;
  }];
}

- (FBFuture<NSNumber *> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration stdOut:(id<FBProcessFileOutput>)stdOut stdErr:(id<FBProcessFileOutput>)stdErr
{
  // Start reading now, but don't block on the resolution, we will ensure that the read has started after the app has launched.
  FBFuture *readingFutures = [FBFuture futureWithFutures:@[
    [stdOut startReading],
    [stdErr startReading],
  ]];

  return [[self
    launchApplication:configuration stdOutPath:stdOut.filePath stdErrPath:stdErr.filePath]
    onQueue:self.simulator.workQueue fmap:^(NSNumber *result) {
      return [readingFutures mapReplace:result];
    }];
}

- (FBFuture<NSNumber *> *)isApplicationRunning:(NSString *)bundleID
{
  return [[self.simulator
    processIDWithBundleID:bundleID]
    onQueue:self.simulator.workQueue chain:^(FBFuture<NSNumber *> *future){
      NSNumber *processIdentifier = future.result;
      return processIdentifier ? [FBFuture futureWithResult:@YES] : [FBFuture futureWithResult:@NO];
    }];
}

- (FBFuture<NSNumber *> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  FBSimulator *simulator = self.simulator;
  NSDictionary<NSString *, id> *options = [FBSimulatorApplicationCommands
    simDeviceLaunchOptionsForConfiguration:configuration
    stdOutPath:[self translateAbsolutePath:stdOutPath toPathRelativeTo:simulator.dataDirectory]
    stdErrPath:[self translateAbsolutePath:stdErrPath toPathRelativeTo:simulator.dataDirectory]];

  FBMutableFuture<NSNumber *> *future = [FBMutableFuture future];

  id<FBControlCoreLogger> logger = self.simulator.logger;
  [logger logFormat:
    @"Launching Application %@ with %@ %@",
    configuration.bundleID,
    [FBCollectionInformation oneLineDescriptionFromArray:configuration.arguments],
    [FBCollectionInformation oneLineDescriptionFromDictionary:configuration.environment]
  ];
  [simulator.device launchApplicationAsyncWithID:configuration.bundleID options:options completionQueue:simulator.workQueue completionHandler:^(NSError *error, pid_t pid){
    if (error) {
      [logger logFormat:@"Failed to launch Application %@ %@", configuration.bundleID, error];
      [future resolveWithError:error];
    } else {
      [logger logFormat:@"Launched Application %@ with pid %d", configuration.bundleID, pid];
      [future resolveWithResult:@(pid)];
    }
  }];
  return future;
}

- (NSString *)translateAbsolutePath:(NSString *)absolutePath toPathRelativeTo:(NSString *)referencePath
{
  if (![absolutePath hasPrefix:@"/"]) {
    return absolutePath;
  }
  // When launching an application with a custom stdout/stderr path, `SimDevice` uses the given path relative
  // to the Simulator's data directory. From the Framework's consumer point of view this might not be the
  // wanted behaviour. To work around it, we construct a path relative to the Simulator's data directory
  // using `..` until we end up in the absolute path outside the Simulator's data directory.
  NSString *translatedPath = @"";
  for (NSUInteger index = 0; index < referencePath.pathComponents.count; index++) {
    translatedPath = [translatedPath stringByAppendingPathComponent:@".."];
  }
  return [translatedPath stringByAppendingPathComponent:absolutePath];
}

+ (NSDictionary<NSString *, id> *)simDeviceLaunchOptionsForConfiguration:(FBApplicationLaunchConfiguration *)configuration stdOutPath:(nullable NSString *)stdOutPath stdErrPath:(nullable NSString *)stdErrPath
{
  NSMutableDictionary<NSString *, id> *options = [[FBSimulatorProcessSpawnCommands launchOptionsWithArguments:configuration.arguments environment:configuration.environment waitForDebugger:configuration.waitForDebugger] mutableCopy];
  if (stdOutPath){
    options[@"stdout"] = stdOutPath;
  }
  if (stdErrPath) {
    options[@"stderr"] = stdErrPath;
  }
  return [options copy];
}

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

  FBBundleDescriptor *bundle = [FBBundleDescriptor bundleFromPath:appPath error:error];
  if (!bundle) {
    return nil;
  }

  return [FBInstalledApplication
    installedApplicationWithBundle:bundle
    installTypeString:typeString
    signerIdentity:nil
    dataContainer:dataContainer.path];
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
      NSSet<NSString *> *supportedArchitectures = [FBiOSTargetConfiguration baseArchsToCompatibleArch:self.simulator.architectures];
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

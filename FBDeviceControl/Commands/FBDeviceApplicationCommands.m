/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceApplicationCommands.h"

#import <objc/runtime.h>

#import "FBAMDServiceConnection.h"
#import "FBDevice+Private.h"
#import "FBDevice.h"
#import "FBDeviceControlError.h"
#import "FBDeviceDebuggerCommands.h"
#import "FBInstrumentsClient.h"
#import <FBDeviceControl/FBDeviceControl-Swift.h>

@interface FBDeviceWorkflowStatistics : NSObject

@property (nonatomic, copy, readonly) NSString *workflowType;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, copy, nullable, readwrite) NSDictionary<NSString *, id> *lastEvent;

@end

@implementation FBDeviceWorkflowStatistics

- (instancetype)initWithWorkflowType:(NSString *)workflowType logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _workflowType = workflowType;
  _logger = logger;

  return self;
}

- (void)pushProgress:(NSDictionary<NSString *, id> *)event
{
  [self.logger logFormat:@"%@ Progress: %@", self.workflowType, [FBCollectionInformation oneLineDescriptionFromDictionary:event]];
  self.lastEvent = event;
}

- (NSString *)summaryOfRecentEvents
{
  NSDictionary<NSString *, id> *lastEvent = self.lastEvent;
  if (!lastEvent) {
    return [NSString stringWithFormat:@"No events from %@", self.lastEvent];
  }
  return [NSString stringWithFormat:@"Last event %@", [FBCollectionInformation oneLineDescriptionFromDictionary:lastEvent]];
}

@end

static void WorkflowCallback(NSDictionary<NSString *, id> *callbackDictionary, FBDeviceWorkflowStatistics *statistics)
{
  [statistics pushProgress:callbackDictionary];
}

@interface FBDeviceApplicationCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;
@property (nonatomic, copy, readonly) NSURL *deltaUpdateDirectory;

- (FBFuture<NSNull *> *)killApplicationWithProcessIdentifier:(pid_t)processIdentifier;

@end

@interface FBDeviceLaunchedApplication : NSObject <FBLaunchedApplication>

@property (nonatomic, strong, readonly) FBDeviceApplicationCommands *commands;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) FBApplicationLaunchConfiguration *configuration;


@end

@implementation FBDeviceLaunchedApplication

@synthesize processIdentifier = _processIdentifier;

- (instancetype)initWithProcessIdentifier:(pid_t)processIdentifier configuration:(FBApplicationLaunchConfiguration *)configuration commands:(FBDeviceApplicationCommands *)commands queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processIdentifier = processIdentifier;
  _configuration = configuration;
  _commands = commands;
  _queue = queue;

  return self;
}

- (FBFuture<NSNull *> *)applicationTerminated
{
  FBDeviceApplicationCommands *commands = self.commands;
  pid_t processIdentifier = self.processIdentifier;
  return [FBMutableFuture.future
    onQueue:self.queue respondToCancellation:^ FBFuture<NSNull *> *{
      return [commands killApplicationWithProcessIdentifier:processIdentifier];
    }];
}

- (NSString *)bundleID
{
  return self.configuration.bundleID;
}

@end

@implementation FBDeviceApplicationCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  NSURL *deltaUpdateDirectory = [target.temporaryDirectory temporaryDirectory];
  return [[self alloc] initWithDevice:target deltaUpdateDirectory:deltaUpdateDirectory];
}

- (instancetype)initWithDevice:(FBDevice *)device deltaUpdateDirectory:(NSURL *)deltaUpdateDirectory
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _deltaUpdateDirectory = deltaUpdateDirectory;
  
  return self;
}

#pragma mark FBApplicationCommands Implementation

- (FBFuture<FBInstalledApplication *> *)installApplicationWithPath:(NSString *)path
{
  // We need to get the bundle identifier of the installed application, in order that we can get install info later.
  NSError *error = nil;
  FBBundleDescriptor *bundle = [FBBundleDescriptor bundleFromPath:path error:&error];
  if (!bundle) {
    return [FBFuture futureWithError:error];
  }

  // Construct the options for the underlying install API. This mirrors as much of Xcode's call to the same API as is reasonable.
  // `@"PreferWifi": @1` may also be passed by Xcode. However, this being preferable is highly dependent on a fast WiFi network and both host/device on the same network. Since this is harder to pick a sane default for this option, this is omitted from the options.
  NSURL *appURL = [NSURL fileURLWithPath:path isDirectory:YES];
  NSDictionary<NSString *, id> *options = @{
    @"CFBundleIdentifier": bundle.identifier,  // Lets the installer know what the Bundle ID is of the passed in artifact.
    @"CloseOnInvalidate": @1,  // Standard arguments of lockdown services to ensure that the socket is closed on teardown.
    @"InvalidateOnDetach": @1,  // Similar to the above.
    @"IsUserInitiated": @1, // Improves installation performance. This has a strong effect on time taken in "VerifyingApplication" stage of installation, which is CPU/IO bound on the attached device.
    @"PackageType": @"Developer", // Signifies that the passed payload is a .app
    @"ShadowParentKey": self.deltaUpdateDirectory, // Must be provided if 'Developer' is the 'PackageType'. Specifies where incremental install data and apps are persisted for faster future installs of the same bundle.
  };

  // Perform the install and lookup the app after.
  return [[[self.device
    connectToDeviceWithPurpose:@"install"]
    onQueue:self.device.workQueue pop:^ FBFuture<NSNull *> * (id<FBDeviceCommands> device) {
      [self.device.logger logFormat:@"Installing Application %@", appURL];
      // 'AMDeviceSecureInstallApplicationBundle' performs:
      // 1) The transfer of the application bundle to the device.
      // 2) The installation of the application after the transfer.
      // 3) The performing of the relevant delta updates in the directory pointed to by 'ShadowParentKey'
      FBDeviceWorkflowStatistics *statistics = [[FBDeviceWorkflowStatistics alloc] initWithWorkflowType:@"Install" logger:device.logger];
      int status = device.calls.SecureInstallApplicationBundle(
        device.amDeviceRef,
        (__bridge CFURLRef _Nonnull)(appURL),
        (__bridge CFDictionaryRef _Nonnull)(options),
        (AMDeviceProgressCallback) WorkflowCallback,
        (__bridge void *) (statistics)
      );
      if (status != 0) {
        NSString *errorMessage = CFBridgingRelease(device.calls.CopyErrorText(status));
        return [[FBDeviceControlError
          describeFormat:@"Failed to install application %@ 0x%x (%@). %@", appURL.lastPathComponent, status, errorMessage, statistics.summaryOfRecentEvents]
          failFuture];
      }
      [self.device.logger logFormat:@"Installed Application %@", appURL];
      return FBFuture.empty;
    }]
    onQueue:self.device.asyncQueue fmap:^(id _) {
      return [self installedApplicationWithBundleID:bundle.identifier];
    }];
}

- (FBFuture<NSNull *> *)deltaInstallApplicationWithPath:(NSString *)path andShadowDirectory:(NSString *)shadowDir
{
  NSString *cacheDirectory = shadowDir;
  if (cacheDirectory == nil) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    cacheDirectory = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"idb"];
  }

  // Ensure that the shadow directory exists as the Apple API will not create it.
  NSError *error = nil;
  [[NSFileManager defaultManager] createDirectoryAtPath:cacheDirectory withIntermediateDirectories:TRUE attributes:nil error:&error];

  NSDictionary *options = @{@"PackageType" : @"Developer", @"ShadowParentKey" : [NSURL fileURLWithPath:cacheDirectory]};
  NSURL *appURL = [NSURL fileURLWithPath:path isDirectory:YES];

  return [self secureDeltaInstallApplication:appURL options:options];
}

- (FBFuture<id> *)uninstallApplicationWithBundleID:(NSString *)bundleID
{
  // It may be better to investigate if FB_AMDeviceSecureUninstallApplication
  // outputs some error message when the bundle id doesn't exist
  // Currently it returns 0 as if it had succeded
  // In case that's not possible, we should look into querying if
  // the app is installed first (FB_AMDeviceLookupApplications)
  return [[self.device
    connectToDeviceWithPurpose:@"uninstall_%@", bundleID]
    onQueue:self.device.workQueue pop:^ FBFuture<NSNull *> * (id<FBDeviceCommands> device) {
      FBDeviceWorkflowStatistics *statistics = [[FBDeviceWorkflowStatistics alloc] initWithWorkflowType:@"Install" logger:device.logger];
      [self.device.logger logFormat:@"Uninstalling Application %@", bundleID];
      int status = device.calls.SecureUninstallApplication(
        0,
        device.amDeviceRef,
        (__bridge CFStringRef _Nonnull)(bundleID),
        0,
        (AMDeviceProgressCallback) WorkflowCallback,
        (__bridge void *) (statistics)
      );
      if (status != 0) {
        NSString *internalMessage = CFBridgingRelease(device.calls.CopyErrorText(status));
        return [[FBDeviceControlError
          describeFormat:@"Failed to uninstall application '%@' with error 0x%x (%@). %@", bundleID, status, internalMessage, statistics.summaryOfRecentEvents]
          failFuture];
      }
      [self.device.logger logFormat:@"Uninstalled Application %@", bundleID];
      return FBFuture.empty;
    }];
}

- (FBFuture<NSArray<FBInstalledApplication *> *> *)installedApplications
{
  return [[self
    installedApplicationsData:FBDeviceApplicationCommands.installedApplicationLookupAttributes]
    onQueue:self.device.asyncQueue map:^(NSDictionary<NSString *, NSDictionary<NSString *, id> *> *applicationData) {
      NSMutableArray<FBInstalledApplication *> *installedApplications = [[NSMutableArray alloc] initWithCapacity:applicationData.count];
      NSEnumerator *objectEnumerator = [applicationData objectEnumerator];
      for (NSDictionary *app in objectEnumerator) {
        if (app == nil) {
          continue;
        }
        FBInstalledApplication *application = [FBDeviceApplicationCommands installedApplicationFromDictionary:app];
        [installedApplications addObject:application];
      }
      return installedApplications;
    }];
}

- (FBFuture<FBInstalledApplication *> *)installedApplicationWithBundleID:(NSString *)bundleID
{
  return [[self
    installedApplicationsData:FBDeviceApplicationCommands.installedApplicationLookupAttributes]
    onQueue:self.device.asyncQueue fmap:^FBFuture *(NSDictionary<NSString *, NSDictionary<NSString *, id> *> *applicationData) {
      NSDictionary<NSString *, id> *app = applicationData[bundleID];
      if (!app) {
        return [[FBDeviceControlError
          describeFormat:@"Application with bundle ID: %@ is not installed. Installed apps %@ ", bundleID, [FBCollectionInformation oneLineDescriptionFromArray:applicationData.allKeys]]
          failFuture];
      }
      FBInstalledApplication *application = [FBDeviceApplicationCommands installedApplicationFromDictionary:app];
      return [FBFuture futureWithResult:application];
   }];
}

- (FBFuture<NSDictionary<NSString *, NSNumber *> *> *)runningApplications
{
  return [[FBFuture
    futureWithFutures:@[
      [self pidToRunningProcessName],
      [self installedApplicationsData:FBDeviceApplicationCommands.namingLookupAttributes],
    ]]
    onQueue:self.device.asyncQueue map:^ NSDictionary<NSString *, NSNumber *> * (NSArray<id> *tuple) {
      // Obtain the requested mappings.
      NSDictionary<NSNumber *, NSString *> *pidToRunningProcessName = tuple[0];
      NSDictionary<NSString *, id> *bundleIdentifierToAttributes = tuple[1];

      // Flip the mappings
      NSMutableDictionary<NSString *, NSString *> *bundleNameToBundleIdentifier = NSMutableDictionary.dictionary;
      for (NSString *bundleIdentifier in bundleIdentifierToAttributes.allKeys) {
        NSString *bundleName = bundleIdentifierToAttributes[bundleIdentifier][FBApplicationInstallInfoKeyBundleName];
        bundleNameToBundleIdentifier[bundleName] = bundleIdentifier;
      }
      NSMutableDictionary<NSString *, NSNumber *> *runningProcessNameToPID = NSMutableDictionary.dictionary;
      for (NSNumber *processIdentifier in pidToRunningProcessName.allKeys) {
        NSString *processName = pidToRunningProcessName[processIdentifier];
        runningProcessNameToPID[processName] = processIdentifier;
      }

      // Compare bundle names with PIDs by using the inverted mappings.
      NSMutableDictionary<NSString *, NSNumber *> *bundleNameToPID = NSMutableDictionary.dictionary;
      for (NSString *processName in runningProcessNameToPID.allKeys) {
        NSString *bundleName = bundleNameToBundleIdentifier[processName];
        if (!bundleName) {
          continue;
        }
        NSNumber *pid = runningProcessNameToPID[processName];
        bundleNameToPID[bundleName] = pid;
      }
      return bundleNameToPID;
    }];
}

- (FBFuture<NSNumber *> *)processIDWithBundleID:(NSString *)bundleID
{
  return [[self
    runningApplications]
    onQueue:self.device.asyncQueue fmap:^(NSDictionary<NSString *, NSNumber *> *result) {
      NSNumber *pid = result[bundleID];
      if (!pid) {
        return [[FBDeviceControlError
          describeFormat:@"No pid for %@", bundleID]
          failFuture];
      }
      return [FBFuture futureWithResult:pid];
    }];
}

- (FBFuture<NSNull *> *)killApplicationWithBundleID:(NSString *)bundleID
{
  return [[self
    processIDWithBundleID:bundleID]
    onQueue:self.device.workQueue fmap:^(NSNumber *processIdentifier) {
      return [self killApplicationWithProcessIdentifier:processIdentifier.intValue];
    }];
}

- (FBFuture<id<FBLaunchedApplication>> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration
{
  if (configuration.launchMode == FBApplicationLaunchModeFailIfRunning) {
    return [[self processIDWithBundleID:configuration.bundleID] onQueue:self.device.asyncQueue chain:^ (FBFuture<NSNumber *>* processIdQueryResult) {
      if (processIdQueryResult.state == FBFutureStateDone) {
        return [[FBDeviceControlError
          describeFormat:@"Application %@ already running with pid %@", configuration.bundleID, processIdQueryResult.result]
          failFuture];
      } else if (processIdQueryResult.state == FBFutureStateFailed) {
        return (FBFuture*)[self launchApplicationIgnoreCurrentState:configuration];
      } else {
        return (FBFuture*)processIdQueryResult;
      }
    }];
  }
  return [self launchApplicationIgnoreCurrentState:configuration];
}

#pragma mark Private

- (FBFuture<id<FBLaunchedApplication>> *)launchApplicationIgnoreCurrentState:(FBApplicationLaunchConfiguration *)configuration
{
    if (self.device.osVersion.version.majorVersion >= 17) {
        FBAppleDevicectlCommandExecutor *devicectl = [[FBAppleDevicectlCommandExecutor alloc] initWithDevice:self.device];
        return [[devicectl launchApplicationWithConfiguration:configuration]
                onQueue:self.device.asyncQueue map:^ id<FBLaunchedApplication> (NSNumber* pid) {
            return [[FBDeviceLaunchedApplication alloc]
                    initWithProcessIdentifier:pid.intValue
                    configuration:configuration
                    commands:self
                    queue:self.device.workQueue];
        }];
    } else {
        return [[[self
                  remoteInstrumentsClient]
                 onQueue:self.device.asyncQueue pop:^(FBInstrumentsClient *client) {
            return [client launchApplication:configuration];
        }]
                onQueue:self.device.asyncQueue map:^ id<FBLaunchedApplication> (NSNumber *pid) {
            return [[FBDeviceLaunchedApplication alloc]
                    initWithProcessIdentifier:pid.intValue
                    configuration:configuration
                    commands:self
                    queue:self.device.workQueue];
        }];
    }
}

- (FBFuture<NSNull *> *)killApplicationWithProcessIdentifier:(pid_t)processIdentifier
{
  return [[self
    remoteInstrumentsClient]
    onQueue:self.device.asyncQueue pop:^(FBInstrumentsClient *client) {
      return [client killProcess:processIdentifier];
    }];
}

- (FBFuture<NSNull *> *)secureInstallApplicationBundle:(NSURL *)hostAppURL options:(NSDictionary<NSString *, id> *)options
{
  return [[self.device
    connectToDeviceWithPurpose:@"install"]
    onQueue:self.device.workQueue pop:^ FBFuture<NSNull *> * (id<FBDeviceCommands> device) {
      FBDeviceWorkflowStatistics *statistics = [[FBDeviceWorkflowStatistics alloc] initWithWorkflowType:@"Install" logger:device.logger];
      [self.device.logger logFormat:@"Installing Application %@", hostAppURL];
      int status = device.calls.SecureInstallApplicationBundle(
        device.amDeviceRef,
        (__bridge CFURLRef _Nonnull)(hostAppURL),
        (__bridge CFDictionaryRef _Nonnull)(options),
        (AMDeviceProgressCallback) WorkflowCallback,
        (__bridge void *) (statistics)
      );
      if (status != 0) {
        NSString *errorMessage = CFBridgingRelease(device.calls.CopyErrorText(status));
          return [[FBDeviceControlError
                    describeFormat:@"Failed to install application %@ 0x%x (%@). %@", [hostAppURL lastPathComponent], status, errorMessage, statistics.summaryOfRecentEvents]
                    failFuture];
        //return [[FBDeviceControlError
        //  describeFormat:@"Failed to install application %@ 0x%x (%@)", [hostAppURL lastPathComponent], status, errorMessage]
        //  failFuture];
      }
      [self.device.logger logFormat:@"Installed Application %@", hostAppURL];
      return FBFuture.empty;
    }];
}

- (FBFuture<NSNull *> *)secureDeltaInstallApplication:(NSURL *)appURL options:(NSDictionary *)options
{
  return [[self.device
    connectToDeviceWithPurpose:@"install"]
    onQueue:self.device.workQueue pop:^ FBFuture<NSNull *> * (id<FBDeviceCommands> device) {
      FBDeviceWorkflowStatistics *statistics = [[FBDeviceWorkflowStatistics alloc] initWithWorkflowType:@"Install" logger:device.logger];
      [self.device.logger logFormat:@"Installing Application %@", appURL];
      int status = device.calls.SecureInstallApplicationBundle(
        device.amDeviceRef,
        (__bridge CFURLRef _Nonnull)(appURL),
        (__bridge CFDictionaryRef _Nonnull)(options),
        (AMDeviceProgressCallback) WorkflowCallback,
        (__bridge void *) (statistics)
      );
      if (status != 0) {
        NSString *errorMessage = CFBridgingRelease(device.calls.CopyErrorText(status));
          return [[FBDeviceControlError
                    describeFormat:@"Failed to install application %@ 0x%x (%@). %@", [appURL lastPathComponent], status, errorMessage, statistics.summaryOfRecentEvents]
                    failFuture];
        //return [[FBDeviceControlError
        //  describeFormat:@"Failed to install application %@ 0x%x (%@)", [appURL lastPathComponent], status, errorMessage]
        //  failFuture];
      }
      [self.device.logger logFormat:@"Installed Application %@", appURL];
      return FBFuture.empty;
    }];
}

- (FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> *)installedApplicationsData:(NSArray<NSString *> *)returnAttributes
{
  return [[self.device
    connectToDeviceWithPurpose:@"installed_apps"]
    onQueue:self.device.workQueue pop:^ FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> * (id<FBDeviceCommands> device) {
      NSDictionary<NSString *, id> *options = @{
        @"ReturnAttributes": returnAttributes,
      };
      CFDictionaryRef applications;
      int status = device.calls.LookupApplications(
        device.amDeviceRef,
        (__bridge CFDictionaryRef _Nullable)(options),
        &applications
      );
      if (status != 0) {
        NSString *errorMessage = CFBridgingRelease(device.calls.CopyErrorText(status));
        return [[FBDeviceControlError
          describeFormat:@"Failed to get list of applications 0x%x (%@)", status, errorMessage]
          failFuture];
      }
      return [FBFuture futureWithResult:CFBridgingRelease(applications)];
    }];
}

- (FBFutureContext<FBInstrumentsClient *> *)remoteInstrumentsClient
{
  // There is a change in service names in iOS 14 that we have to account for.
  // Both of these channels are fine to use with the same underlying protocol, so long as the secure wrapper is used on the transport.
  BOOL usesSecureConnection = self.device.osVersion.version.majorVersion >= 14;
  return [[[self.device
    ensureDeveloperDiskImageIsMounted]
    onQueue:self.device.workQueue pushTeardown:^(id _) {
      return [self.device startService:(usesSecureConnection ? @"com.apple.instruments.remoteserver.DVTSecureSocketProxy" : @"com.apple.instruments.remoteserver")];
    }]
    onQueue:self.device.asyncQueue pend:^(FBAMDServiceConnection *connection) {
      return [FBInstrumentsClient instrumentsClientWithServiceConnection:connection logger:self.device.logger];
    }];
}

- (FBFuture<NSDictionary<NSNumber *, NSString *> *> *)pidToRunningProcessName
{
  return [[self.device
    startService:@"com.apple.os_trace_relay"]
    onQueue:self.device.asyncQueue pop:^(FBAMDServiceConnection *connection) {
      NSError *error = nil;
      BOOL success = [connection sendMessage:@{@"Request": @"PidList"} error:&error];
      if (!success) {
        return [[FBDeviceControlError
          describeFormat:@"Failed to request PidList %@", error]
          failFuture];
      }
      NSData *data = [connection receive:1 error:&error];
      if (!data) {
        return [[FBDeviceControlError
          describeFormat:@"Failed to receive 1 byte after PidList %@", error]
          failFuture];
      }
      NSDictionary<NSString *, id> *response = [connection receiveMessageWithError:&error];
      if (!response) {
        return [[FBDeviceControlError
          describeFormat:@"Failed to receive PidList response %@", error]
          failFuture];
      }
      NSString *status = response[@"Status"];
      if (![status isEqualToString:@"RequestSuccessful"]) {
        return [[FBDeviceControlError
          describeFormat:@"Request to PidList is not RequestSuccessful %@", error]
          failFuture];
      }
      NSDictionary<NSString *, id> *payload = response[@"Payload"];
      NSMutableDictionary<NSNumber *, NSString *> *pidToRunningProcessName = NSMutableDictionary.dictionary;
      for (NSString *processIdentifer in payload.keyEnumerator) {
        NSDictionary<NSString *, NSString *> *contents = payload[processIdentifer];
        NSString *processName = contents[@"ProcessName"];
        if (![processName isKindOfClass:NSString.class]) {
          continue;
        }
        NSNumber* processIdentiferNumber = [NSNumber numberWithInteger:[processIdentifer integerValue]];
        pidToRunningProcessName[processIdentiferNumber] = processName;
      }
      return [FBFuture futureWithResult:pidToRunningProcessName];
    }];
}

+ (FBInstalledApplication *)installedApplicationFromDictionary:(NSDictionary<NSString *, id> *)app
{
  NSString *bundleName = app[FBApplicationInstallInfoKeyBundleName] ?: @"";
  NSString *path = app[FBApplicationInstallInfoKeyPath] ?: @"";
  NSString *bundleID = app[FBApplicationInstallInfoKeyBundleIdentifier];

  FBBundleDescriptor *bundle = [[FBBundleDescriptor alloc] initWithName:bundleName identifier:bundleID path:path binary:nil];

  return [FBInstalledApplication
    installedApplicationWithBundle:bundle
    installTypeString:(app[FBApplicationInstallInfoKeyApplicationType] ?: @"")
    signerIdentity:(app[FBApplicationInstallInfoKeySignerIdentity] ? : @"")
    dataContainer:nil];
}

+ (NSArray<NSString *> *)installedApplicationLookupAttributes
{
  static dispatch_once_t onceToken;
  static NSArray<NSString *> *lookupAttributes = nil;
  dispatch_once(&onceToken, ^{
    lookupAttributes = @[
      FBApplicationInstallInfoKeyApplicationType,
      FBApplicationInstallInfoKeyBundleIdentifier,
      FBApplicationInstallInfoKeyBundleName,
      FBApplicationInstallInfoKeyPath,
      FBApplicationInstallInfoKeySignerIdentity,
    ];
  });
  return lookupAttributes;
}

+ (NSArray<NSString *> *)namingLookupAttributes
{
  static dispatch_once_t onceToken;
  static NSArray<NSString *> *lookupAttributes = nil;
  dispatch_once(&onceToken, ^{
    lookupAttributes = @[
      FBApplicationInstallInfoKeyBundleIdentifier,
      FBApplicationInstallInfoKeyBundleName,
    ];
  });
  return lookupAttributes;
}

@end

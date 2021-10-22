/*
 * Copyright (c) Facebook, Inc. and its affiliates.
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

static void UninstallCallback(NSDictionary<NSString *, id> *callbackDictionary, id<FBDeviceCommands> device)
{
  [device.logger logFormat:@"Uninstall Progress: %@", [FBCollectionInformation oneLineDescriptionFromDictionary:callbackDictionary]];
}

static void InstallCallback(NSDictionary<NSString *, id> *callbackDictionary, id<FBDeviceCommands> device)
{
  [device.logger logFormat:@"Install Progress: %@", [FBCollectionInformation oneLineDescriptionFromDictionary:callbackDictionary]];
}

@interface FBDeviceApplicationCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;
@property (nonatomic, copy, readonly) NSURL *deltaUpdateDirectory;

- (FBFuture<NSNull *> *)killApplicationWithProcessIdentifier:(pid_t)processIdentifier;

@end

@interface FBDeviceLaunchedApplication : NSObject <FBLaunchedApplication>

@property (nonatomic, strong, readonly) FBDeviceApplicationCommands *commands;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBDeviceLaunchedApplication

@synthesize processIdentifier = _processIdentifier;

- (instancetype)initWithProcessIdentifier:(pid_t)processIdentifier commands:(FBDeviceApplicationCommands *)commands queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processIdentifier = processIdentifier;
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

- (FBFuture<NSNull *> *)installApplicationWithPath:(NSString *)path
{
  // 'PackageType=Developer' signifies that the passed payload is a .app
  // 'AMDeviceSecureInstallApplicationBundle' performs:
  // 1) The transfer of the application bundle to the device.
  // 2) The installation of the application after the transfer.
  // 3) The performing of the relevant delta updates in the directory pointed to by 'ShadowParentKey'
  // 'ShadowParentKey' must be provided in 'AMDeviceSecureInstallApplicationBundle' if 'Developer' is the 'PackageType
  NSURL *appURL = [NSURL fileURLWithPath:path isDirectory:YES];
  NSDictionary<NSString *, id> *options = @{
    @"PackageType" : @"Developer",
    @"ShadowParentKey": self.deltaUpdateDirectory,
  };
  return [self secureInstallApplicationBundle:appURL options:options];
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
      [self.device.logger logFormat:@"Uninstalling Application %@", bundleID];
      int status = device.calls.SecureUninstallApplication(
        0,
        device.amDeviceRef,
        (__bridge CFStringRef _Nonnull)(bundleID),
        0,
        (AMDeviceProgressCallback) UninstallCallback,
        (__bridge void *) (device)
      );
      if (status != 0) {
        NSString *internalMessage = CFBridgingRelease(device.calls.CopyErrorText(status));
        return [[FBDeviceControlError
          describeFormat:@"Failed to uninstall application '%@' with error 0x%x (%@)", bundleID, status, internalMessage]
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
      [self runningProcessNameToPID],
      [self installedApplicationsData:FBDeviceApplicationCommands.namingLookupAttributes],
    ]]
    onQueue:self.device.asyncQueue map:^ NSDictionary<NSString *, NSNumber *> * (NSArray<id> *tuple) {
      NSDictionary<NSString *, NSNumber *> *runningProcessNameToPID = tuple[0];
      NSDictionary<NSString *, id> *bundleIdentifierToAttributes = tuple[1];
      NSMutableDictionary<NSString *, NSString *> *bundleNameToBundleIdentifier = NSMutableDictionary.dictionary;
      for (NSString *bundleIdentifier in bundleIdentifierToAttributes.allKeys) {
        NSString *bundleName = bundleIdentifierToAttributes[bundleIdentifier][FBApplicationInstallInfoKeyBundleName];
        bundleNameToBundleIdentifier[bundleName] = bundleIdentifier;
      }
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
  return [[[self
    remoteInstrumentsClient]
    onQueue:self.device.asyncQueue pop:^(FBInstrumentsClient *client) {
      return [client launchApplication:configuration];
    }]
    onQueue:self.device.asyncQueue map:^ id<FBLaunchedApplication> (NSNumber *pid) {
      return [[FBDeviceLaunchedApplication alloc] initWithProcessIdentifier:pid.intValue commands:self queue:self.device.workQueue];
    }];
}

#pragma mark Private

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
      [self.device.logger logFormat:@"Installing Application %@", hostAppURL];
      int status = device.calls.SecureInstallApplicationBundle(
        device.amDeviceRef,
        (__bridge CFURLRef _Nonnull)(hostAppURL),
        (__bridge CFDictionaryRef _Nonnull)(options),
        (AMDeviceProgressCallback) InstallCallback,
        (__bridge void *) (device)
      );
      if (status != 0) {
        NSString *errorMessage = CFBridgingRelease(device.calls.CopyErrorText(status));
        return [[FBDeviceControlError
          describeFormat:@"Failed to install application %@ 0x%x (%@)", [hostAppURL lastPathComponent], status, errorMessage]
          failFuture];
      }
      [self.device.logger logFormat:@"Installed Application %@", hostAppURL];
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

- (FBFuture<NSDictionary<NSString *, NSNumber *> *> *)runningProcessNameToPID
{
  return [[self
    remoteInstrumentsClient]
    onQueue:self.device.asyncQueue pop:^(FBInstrumentsClient *client) {
      return [client runningApplications];
    }];
}

+ (FBInstalledApplication *)installedApplicationFromDictionary:(NSDictionary<NSString *, id> *)app
{
  NSString *bundleName = app[FBApplicationInstallInfoKeyBundleName] ?: @"";
  NSString *path = app[FBApplicationInstallInfoKeyPath] ?: @"";
  NSString *bundleID = app[FBApplicationInstallInfoKeyBundleIdentifier];
  FBApplicationInstallType installType = [FBInstalledApplication
    installTypeFromString:(app[FBApplicationInstallInfoKeyApplicationType] ?: @"")
    signerIdentity:(app[FBApplicationInstallInfoKeySignerIdentity] ? : @"")];

  FBBundleDescriptor *bundle = [[FBBundleDescriptor alloc] initWithName:bundleName identifier:bundleID path:path binary:nil];

  return [FBInstalledApplication
    installedApplicationWithBundle:bundle
    installType:installType];
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

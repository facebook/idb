/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceApplicationCommands.h"

#import <objc/runtime.h>

#import "FBAMDevice+Private.h"
#import "FBAMDevice.h"
#import "FBAMDServiceConnection.h"
#import "FBDevice+Private.h"
#import "FBDevice.h"
#import "FBDeviceApplicationLaunchStrategy.h"
#import "FBDeviceControlError.h"
#import "FBDeviceDebuggerCommands.h"
#import "FBiOSDeviceOperator.h"

static void UninstallCallback(NSDictionary<NSString *, id> *callbackDictionary, FBAMDevice *device)
{
  [device.logger logFormat:@"Uninstall Progress: %@", [FBCollectionInformation oneLineDescriptionFromDictionary:callbackDictionary]];
}

static void InstallCallback(NSDictionary<NSString *, id> *callbackDictionary, FBAMDevice *device)
{
  [device.logger logFormat:@"Install Progress: %@", [FBCollectionInformation oneLineDescriptionFromDictionary:callbackDictionary]];
}

static void TransferCallback(NSDictionary<NSString *, id> *callbackDictionary, FBAMDevice *device)
{
  [device.logger logFormat:@"Transfer Progress: %@", [FBCollectionInformation oneLineDescriptionFromDictionary:callbackDictionary]];
}

@interface FBDeviceApplicationCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceApplicationCommands

#pragma mark Initializers

+ (FBInstalledApplication *)installedApplicationFromDictionary:(NSDictionary<NSString *, id> *)app
{
  NSString *bundleName = app[FBApplicationInstallInfoKeyBundleName] ?: @"";
  NSString *path = app[FBApplicationInstallInfoKeyPath] ?: @"";
  NSString *bundleID = app[FBApplicationInstallInfoKeyBundleIdentifier];
  FBApplicationBundle *bundle = [FBApplicationBundle
                                 applicationWithName:bundleName
                                 path:path
                                 bundleID:bundleID];

  NSString *installTypeString = app[FBApplicationInstallInfoKeyApplicationType] ?: @"";
  FBApplicationInstallType installType = [FBInstalledApplication installTypeFromString:installTypeString];
  FBInstalledApplication *application = [FBInstalledApplication
                                         installedApplicationWithBundle:bundle
                                         installType:installType];
  return application;
}

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  return [[self alloc] initWithDevice:target];
}

- (instancetype)initWithDevice:(FBDevice *)device
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;

  return self;
}

#pragma mark FBApplicationCommands Implementation

- (FBFuture<NSNull *> *)installApplicationWithPath:(NSString *)path
{
  NSURL *appURL = [NSURL fileURLWithPath:path isDirectory:YES];
  NSDictionary *options = @{@"PackageType" : @"Developer"};
  return [[self
    transferAppURL:appURL options:options]
    onQueue:self.device.workQueue fmap:^(NSNull *_) {
      return [self secureInstallApplication:appURL options:options];
    }];
}

- (FBFuture<id> *)uninstallApplicationWithBundleID:(NSString *)bundleID
{
  // It may be better to investigate if FB_AMDeviceSecureUninstallApplication
  // outputs some error message when the bundle id doesn't exist
  // Currently it returns 0 as if it had succeded
  // In case that's not possible, we should look into querying if
  // the app is installed first (FB_AMDeviceLookupApplications)
  return [[self.device.amDevice
    connectToDeviceWithPurpose:@"uninstall_%@", bundleID]
    onQueue:self.device.workQueue pop:^(FBAMDevice *device) {
      [self.device.logger logFormat:@"Uninstalling Application %@", bundleID];
      int status = self.device.amDevice.calls.SecureUninstallApplication(
        0,
        device.amDevice,
        (__bridge CFStringRef _Nonnull)(bundleID),
        0,
        (AMDeviceProgressCallback) UninstallCallback,
        (__bridge void *) (device)
      );
      if (status != 0) {
        NSString *internalMessage = CFBridgingRelease(device.calls.CopyErrorText(status));
        return [[FBDeviceControlError
          describeFormat:@"Failed to uninstall application '%@' with error (%@)", bundleID, internalMessage]
          failFuture];
      }
      [self.device.logger logFormat:@"Uninstalled Application %@", bundleID];
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

- (FBFuture<NSArray<FBInstalledApplication *> *> *)installedApplications
{
  return [[self
    installedApplicationsData]
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
   installedApplicationsData]
   onQueue:self.device.asyncQueue fmap:^FBFuture *(NSDictionary<NSString *, NSDictionary<NSString *, id> *> *applicationData) {
     NSDictionary <NSString *, id> *app = applicationData[bundleID];
     if (!app) {
       return [[FBDeviceControlError describeFormat:@"Application with bundle ID: %@ is not installed", bundleID] failFuture];
     }
     FBInstalledApplication *application = [FBDeviceApplicationCommands installedApplicationFromDictionary:app];
     return [FBFuture futureWithResult:application];
   }];
}

- (FBFuture<NSDictionary<NSString *, FBProcessInfo *> *> *)runningApplications
{
  // TODO: This is unimplemented, yet. Adding "empty" implementation so that it will not crash on selector forwarding
  return [FBFuture futureWithResult:@{}];
}

- (FBFuture<NSNumber *> *)isApplicationInstalledWithBundleID:(NSString *)bundleID
{
  return [[self
    installedApplicationWithBundleID:bundleID]
    onQueue:self.device.workQueue chain:^(FBFuture *future) {
      return [FBFuture futureWithResult:(future.state == FBFutureStateDone ? @YES : @NO)];
    }];
}

- (FBFuture<NSNull *> *)killApplicationWithBundleID:(NSString *)bundleID
{
  return [((FBiOSDeviceOperator *) self.device.deviceOperator) killApplicationWithBundleID:bundleID];
}

- (FBFuture<NSNumber *> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration
{
  __block NSString *remoteAppPath = nil;
  return [[[self
    remoteApplicationPathForConfiguration:configuration]
    onQueue:self.device.workQueue pushTeardown:^(NSString *result) {
      remoteAppPath = result;
      return [[FBDeviceDebuggerCommands
        commandsWithTarget:self.device]
        connectToDebugServer];
    }]
    onQueue:self.device.workQueue pop:^(FBAMDServiceConnection *connection) {
      return [[FBDeviceApplicationLaunchStrategy
        strategyWithDebugConnection:connection logger:self.device.logger]
        launchApplication:configuration remoteAppPath:remoteAppPath];
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)transferAppURL:(NSURL *)appURL options:(NSDictionary *)options
{
  return [FBFuture onQueue:self.device.workQueue resolve:^ {
    int status = self.device.amDevice.calls.SecureTransferPath(
      0,
      self.device.amDevice.amDevice,
      (__bridge CFURLRef _Nonnull)(appURL),
      (__bridge CFDictionaryRef _Nonnull)(options),
      (AMDeviceProgressCallback) TransferCallback,
      (__bridge void *) (self.device.amDevice)
    );
    if (status != 0) {
      NSString *internalMessage = CFBridgingRelease(self.device.amDevice.calls.CopyErrorText(status));
      return [[FBDeviceControlError
        describeFormat:@"Failed to transfer '%@' with error (%@)", appURL, internalMessage]
        failFuture];
    }
    return [FBFuture futureWithResult:NSNull.null];
  }];
}

- (FBFuture<NSNull *> *)secureInstallApplication:(NSURL *)appURL options:(NSDictionary *)options
{
  return [[self.device.amDevice
    connectToDeviceWithPurpose:@"install"]
    onQueue:self.device.workQueue pop:^(FBAMDevice *device) {
      [self.device.logger logFormat:@"Installing Application %@", appURL];
      int installReturnCode = self.device.amDevice.calls.SecureInstallApplication(
        0,
        device.amDevice,
        (__bridge CFURLRef _Nonnull)(appURL),
        (__bridge CFDictionaryRef _Nonnull)(options),
        (AMDeviceProgressCallback) InstallCallback,
        (__bridge void *) (self.device.amDevice)
      );
      if (installReturnCode != 0) {
        NSString *errorMessage = CFBridgingRelease(self.device.amDevice.calls.CopyErrorText(installReturnCode));
        return [[FBDeviceControlError
          describeFormat:@"Failed to install application %@ (%@)", [appURL lastPathComponent], errorMessage]
          failFuture];
      }
      [self.device.logger logFormat:@"Installed Application %@", appURL];
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

- (FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> *)installedApplicationsData
{
  return [[self.device.amDevice
    connectToDeviceWithPurpose:@"installed_apps"]
    onQueue:self.device.workQueue pop:^ FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> * (FBAMDevice *device) {
      CFDictionaryRef cf_apps;
      int returnCode = self.device.amDevice.calls.LookupApplications(device.amDevice, NULL, &cf_apps);
      if (returnCode != 0) {
        return [[FBDeviceControlError
          describe:@"Failed to get list of applications"]
          failFuture];
      }
      NSDictionary<NSString *, NSDictionary<NSString *, id> *> *apps = CFBridgingRelease(cf_apps);
      return [FBFuture futureWithResult:apps];
    }];
}

- (FBFuture<NSString *> *)remoteApplicationPathForConfiguration:(FBApplicationLaunchConfiguration *)configuration
{
  return [[self
    installedApplicationWithBundleID:configuration.bundleID]
    onQueue:self.device.workQueue map:^(FBInstalledApplication *installedApplication) {
      return installedApplication.bundle.path;
    }];
}

@end

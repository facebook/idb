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
#import "FBDeviceControlError.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

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

#pragma mark Private

- (FBFuture<NSNull *> *)transferAppURL:(NSURL *)appURL options:(NSDictionary *)options
{
  return [[self.device.amDevice
    startAFCService]
    onQueue:self.device.workQueue fmap:^(FBAMDServiceConnection *connection) {
      int transferReturnCode = self.device.amDevice.calls.SecureTransferPath(
        0,
        connection.device,
        (__bridge CFURLRef _Nonnull)(appURL),
        (__bridge CFDictionaryRef _Nonnull)(options),
        NULL,
        0
      );
      if (transferReturnCode != 0) {
        return [[FBDeviceControlError
          describeFormat:@"Failed to transfer path with error code: %x", transferReturnCode]
          failFuture];
      }
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

- (FBFuture<NSNull *> *)secureInstallApplication:(NSURL *)appURL options:(NSDictionary *)options
{
  return [[self.device.amDevice
    startAFCService]
    onQueue:self.device.workQueue fmap:^(FBAMDServiceConnection *connection) {
      int installReturnCode = self.device.amDevice.calls.SecureInstallApplication(
        0,
        connection.device,
        (__bridge CFURLRef _Nonnull)(appURL),
        (__bridge CFDictionaryRef _Nonnull)(options),
        NULL,
        0
      );
      if (installReturnCode != 0) {
        NSString *errorMessage = CFBridgingRelease(self.device.amDevice.calls.CopyErrorText(installReturnCode));
        return [[FBDeviceControlError
          describeFormat:@"Failed to install application (%@)", errorMessage]
          failFuture];
      }
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

- (FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> *)installedApplicationsData
{
  return [[self.device.amDevice
    connectToDevice]
    onQueue:self.device.workQueue fmap:^ FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> * (FBAMDeviceConnection *connection) {
      CFDictionaryRef cf_apps;
      int returnCode = self.device.amDevice.calls.LookupApplications(connection.device, NULL, &cf_apps);
      if (returnCode != 0) {
        return [[FBDeviceControlError
          describe:@"Failed to get list of applications"]
          failFuture];
      }
      NSDictionary<NSString *, NSDictionary<NSString *, id> *> *apps = CFBridgingRelease(cf_apps);
      return [FBFuture futureWithResult:apps];
    }];
}

#pragma mark FBApplicationCommands Implementation

- (FBFuture<NSNull *> *)installApplicationWithPath:(NSString *)path
{
  NSURL *appURL = [NSURL fileURLWithPath:path isDirectory:YES];
  NSDictionary *options = @{@"PackageType" : @"Developer"};
  return [[self
    transferAppURL:appURL options:options]
    onQueue:self.device.workQueue fmap:^FBFuture *(NSNull *_) {
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
    connectToDevice]
    onQueue:self.device.workQueue fmap:^(FBAMDeviceConnection *connectedDevice) {
      int returnCode = self.device.amDevice.calls.SecureUninstallApplication(
        0,
        connectedDevice.device,
        (__bridge CFStringRef _Nonnull)(bundleID),
        0,
        NULL,
        0
      );
      if (returnCode != 0) {
        return [[FBDeviceControlError
          describeFormat:@"Failed to uninstall application with error code %x", returnCode]
          failFuture];
      }
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

#pragma mark Forwarding

+ (BOOL)isSelectorFromProtocolImplementation:(SEL)selector
{
  Protocol *protocol = @protocol(FBApplicationCommands);
  struct objc_method_description description = protocol_getMethodDescription(protocol, selector, YES, YES);
  return description.name != NULL;
}

+ (BOOL)instancesRespondToSelector:(SEL)selector
{
  if ([self isSelectorFromProtocolImplementation:selector]) {
    return YES;
  }
  return [super instancesRespondToSelector:selector];
}

- (BOOL)respondsToSelector:(SEL)selector
{
  if ([self.class isSelectorFromProtocolImplementation:selector]) {
    return YES;
  }
  return [super respondsToSelector:selector];
}

- (id)forwardingTargetForSelector:(SEL)selector
{
  // FBDeviceApplicationCommands doesn't itself implement all FBApplicationCommands methods.
  // So forward to the Device Operator where appropriate.
  id<FBDeviceOperator> operator = self.device.deviceOperator;
  if ([operator respondsToSelector:selector]) {
    return operator;
  }
  return [super forwardingTargetForSelector:selector];
}

@end

#pragma clang diagnostic pop

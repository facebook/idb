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

#import "FBDevice.h"
#import "FBAMDevice.h"
#import "FBAMDevice+Private.h"
#import "FBDeviceControlError.h"
#import "FBDevice+Private.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBDeviceApplicationCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceApplicationCommands

#pragma mark Initializers

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

- (FBFuture *)handleWithAFCSession:(id(^)(CFTypeRef device, NSError **))operationBlock
{
  return [self.device.amDevice futureForDeviceOperation:^(CFTypeRef device, NSError **error) {
    int afcConn;
    int afcReturnCode = FBAMDeviceSecureStartService(device, CFSTR("com.apple.afc"), NULL, &afcConn);
    if (afcReturnCode != 0) {
      return [[FBDeviceControlError
        describeFormat:@"Failed to start afc service with error code: %x", afcReturnCode]
        fail:error];
    }
    id operationResult = operationBlock(device, error);
    close(afcConn);
    return operationResult;
  }];
}

- (FBFuture<NSNull *> *)transferAppURL:(NSURL *)appURL options:(NSDictionary *)options
{
  return [self handleWithAFCSession:^NSNull *(CFTypeRef device, NSError **error){
    int transferReturnCode = FBAMDeviceSecureTransferPath(
      0,
      device,
      (__bridge CFURLRef _Nonnull)(appURL),
      (__bridge CFDictionaryRef _Nonnull)(options),
      NULL,
      0
    );
    if (transferReturnCode != 0) {
      return [[FBDeviceControlError
        describeFormat:@"Failed to transfer path with error code: %x", transferReturnCode]
        fail:error];
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSNull *> *)secureInstallApplication:(NSURL *)appURL options:(NSDictionary *)options
{
  return [self handleWithAFCSession:^NSNull *(CFTypeRef device, NSError **error) {
    int installReturnCode = FBAMDeviceSecureInstallApplication(
      0,
      device,
      (__bridge CFURLRef _Nonnull)(appURL),
      (__bridge CFDictionaryRef _Nonnull)(options),
      NULL,
      0
    );
    if (installReturnCode != 0) {
      return [[FBDeviceControlError
        describe:@"Failed to install application"]
        fail:error];
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)installedApplicationsData
{
  return [self.device.amDevice futureForDeviceOperation:^NSArray<NSDictionary<NSString *, id> *> *(CFTypeRef device, NSError **error) {
    CFDictionaryRef cf_apps;
    int returnCode = FBAMDeviceLookupApplications(device, 0, &cf_apps);
    if (returnCode != 0) {
      return [[FBDeviceControlError
        describe:@"Failed to get list of applications"]
        fail:error];
    }
    NSDictionary *apps = CFBridgingRelease(cf_apps);
    return [apps allValues];
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
  // It may be better to investigate if FBAMDeviceSecureUninstallApplication
  // outputs some error message when the bundle id doesn't exist
  // Currently it returns 0 as if it had succeded
  // In case that's not possible, we should look into querying if
  // the app is installed first (FBAMDeviceLookupApplications)
  return [self.device.amDevice futureForDeviceOperation:^id(CFTypeRef device, NSError **error) {
    int returnCode = FBAMDeviceSecureUninstallApplication(
      0,
      device,
      (__bridge CFStringRef _Nonnull)(bundleID),
      0,
      NULL,
      0
    );
    if (returnCode != 0) {
      return [[FBDeviceControlError
        describeFormat:@"Failed to uninstall application with error code %x", returnCode]
        fail:error];
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSArray<FBInstalledApplication *> *> *)installedApplications
{
  return [[self
    installedApplicationsData]
    onQueue:self.device.asyncQueue map:^(NSArray<NSDictionary<NSString *, id> *> *applicationData) {
      NSMutableArray<FBInstalledApplication *> *installedApplications = [[NSMutableArray alloc] init];
      for (NSDictionary *app in applicationData) {
        if (app == nil) {
          continue;
        }
        FBApplicationBundle *bundle = [FBApplicationBundle
          applicationWithName:[app valueForKey:FBApplicationInstallInfoKeyBundleName] ?: @""
          path:[app valueForKey:FBApplicationInstallInfoKeyPath] ?: @""
          bundleID:app[FBApplicationInstallInfoKeyBundleIdentifier]];
        FBApplicationInstallType installType = [FBInstalledApplication
          installTypeFromString:[app valueForKey:FBApplicationInstallInfoKeyApplicationType] ?: @""];
        FBInstalledApplication *application = [FBInstalledApplication
          installedApplicationWithBundle:bundle
          installType:installType];
        [installedApplications addObject:application];
      }
      return [installedApplications copy];
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

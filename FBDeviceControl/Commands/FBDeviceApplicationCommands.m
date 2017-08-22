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

#pragma mark FBApplicationCommands Implementation

- (id)handleWithAFCSession:(id(^)(void))operationBlock error:(NSError **)error
{
  __block NSError *innerError = nil;
  id result = [self.device.amDevice handleWithBlockDeviceSession:^(CFTypeRef device) {
    int afcConn;
    int afcReturnCode = FBAMDeviceSecureStartService(device, CFSTR("com.apple.afc"), NULL, &afcConn);
    if (afcReturnCode != 0) {
      return [[FBDeviceControlError
        describeFormat:@"Failed to start afc service with error code: %x", afcReturnCode]
        fail:&innerError];
    }
    id operationResult = operationBlock();
    close(afcConn);
    return operationResult;
  } error: error];
  *error = innerError;
  return result;
}

- (BOOL)transferAppURL:(NSURL *)app_url options:(NSDictionary *)options error:(NSError **)error
{
  id transferReturnCode = [self handleWithAFCSession:^id() {
    return @(FBAMDeviceSecureTransferPath(0,
      self.device.amDevice.amDevice,
      (__bridge CFURLRef _Nonnull)(app_url),
      (__bridge CFDictionaryRef _Nonnull)(options),
      NULL,
    0));
  } error:error];

  if (transferReturnCode == nil) {
    return [[FBDeviceControlError
      describe:@"Failed to transfer path"]
      failBool:error];
  }

  if ([transferReturnCode intValue] != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to transfer path with error code: %x", [transferReturnCode intValue]]
      failBool:error];
  }
  return YES;
}

- (BOOL)secureInstallApplication:(NSURL *)app_url options:(NSDictionary *)options error:(NSError **)error
{
  NSNumber *install_return_code = [self.device.amDevice handleWithBlockDeviceSession:^id(CFTypeRef device) {
    return @(FBAMDeviceSecureInstallApplication(0, device, (__bridge CFURLRef _Nonnull)(app_url), (__bridge CFDictionaryRef _Nonnull)(options), NULL, 0));
  } error: error];

  if (install_return_code == nil) {
    return [[FBDeviceControlError
      describe:@"Failed to install application"]
      failBool:error];
  }
  if ([install_return_code intValue] != 0) {
    return [[FBDeviceControlError
      describe:@"Failed to install application"]
      failBool:error];
  }
  return YES;
}

- (BOOL)installApplicationWithPath:(NSString *)path error:(NSError **)error
{
  NSURL *app_url = [NSURL fileURLWithPath:path isDirectory:YES];
  NSDictionary *options = @{@"PackageType" : @"Developer"};
  NSError *inner_error = nil;
  if (![self transferAppURL:app_url options:options error:&inner_error] ||
      ![self secureInstallApplication:app_url options:options error:&inner_error])
  {
    return [[[FBDeviceControlError
      describeFormat:@"Failed to install application with path %@", path]
      causedBy:inner_error]
      failBool:error];
  }

  return YES;
}

- (BOOL)uninstallApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSError *innerError = nil;
  NSNumber *returnCode = [self.device.amDevice handleWithBlockDeviceSession:^id(CFTypeRef device) {
    return @(FBAMDeviceSecureUninstallApplication(0, device, (__bridge CFStringRef _Nonnull)(bundleID), 0, NULL, 0));
  } error: &innerError];

  if (returnCode == nil) {
    return [[[FBDeviceControlError
      describe:@"Failed to uninstall application"]
      causedBy:innerError]
      failBool:error];
  }
  if ([returnCode intValue] != 0) {
    return [[[FBDeviceControlError
      describeFormat:@"Failed to uninstall application with error code %x", [returnCode intValue]]
      causedBy:innerError]
      failBool:error];
  }
  return YES;
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

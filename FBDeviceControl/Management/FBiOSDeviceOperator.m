/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBiOSDeviceOperator.h"
#import "FBiOSDeviceOperator+Private.h"

#import <objc/runtime.h>

#import <DTDeviceKitBase/DTDKRemoteDeviceConsoleController.h>
#import <DTDeviceKitBase/DTDKRemoteDeviceToken.h>

#import <DTXConnectionServices/DTXChannel.h>
#import <DTXConnectionServices/DTXMessage.h>

#import <DVTFoundation/DVTDeviceManager.h>
#import <DVTFoundation/DVTFuture.h>

#import <IDEiOSSupportCore/DVTiOSDevice.h>

#import <FBControlCore/FBControlCore.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBDeviceControlError.h"
#import "FBDeviceControlFrameworkLoader.h"

static const NSUInteger FBMaxConosleMarkerLength = 1000;

@protocol DVTApplication <NSObject>
- (NSString *)installedPath;
- (NSString *)containerPath;
- (NSString *)identifier;
- (NSString *)executableName;
@end

@implementation FBiOSDeviceOperator

@synthesize dvtDevice = _dvtDevice;

- (instancetype)initWithiOSDevice:(DVTiOSDevice *)iosDevice
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _dvtDevice = iosDevice;

  return self;
}

#pragma mark Type Coercions

- (DVTiOSDevice *)iosDevice
{
  return (DVTiOSDevice *) self.dvtDevice;
}

#pragma mark - Device specific operations

- (NSString *)containerPathForApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  id<DVTApplication> app = [self installedApplicationWithBundleIdentifier:bundleID];
  return [app containerPath];
}

- (NSString *)applicationPathForApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  id<DVTApplication> app = [self installedApplicationWithBundleIdentifier:bundleID];
  return [app installedPath];
}

- (id<DVTApplication>)installedApplicationWithBundleIdentifier:(NSString *)bundleID
{
  if (!self.iosDevice.applications) {
    [FBRunLoopSpinner spinUntilBlockFinished:^id{
      DVTFuture *future = self.iosDevice.token.fetchApplications;
      [future waitUntilFinished];
      return nil;
    }];
  }
  return [self.iosDevice installedApplicationWithBundleIdentifier:bundleID];
}

- (FBProductBundle *)applicationBundleWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  id<DVTApplication> application = [self installedApplicationWithBundleIdentifier:bundleID];
  if (!application) {
    return nil;
  }

  FBProductBundle *productBundle =
  [[[[[FBProductBundleBuilder builder]
      withBundlePath:[application installedPath]]
     withBundleID:[application identifier]]
    withBinaryName:[application executableName]]
   build];

  return productBundle;
}

- (BOOL)uploadApplicationDataAtPath:(NSString *)path bundleID:(NSString *)bundleID error:(NSError **)error
{
  return
  [[FBRunLoopSpinner spinUntilBlockFinished:^id{
    return @([self.iosDevice uploadApplicationDataWithPath:path forInstalledApplicationWithBundleIdentifier:bundleID error:error]);
  }] boolValue];
}

- (BOOL)cleanApplicationStateWithBundleIdentifier:(NSString *)bundleIdentifier error:(NSError **)error
{
  id returnObject =
  [FBRunLoopSpinner spinUntilBlockFinished:^id{
    if ([self.iosDevice installedApplicationWithBundleIdentifier:bundleIdentifier]) {
      return [self.iosDevice uninstallApplicationWithBundleIdentifierSync:bundleIdentifier];
    }
    return nil;
  }];
  if ([returnObject isKindOfClass:NSError.class]) {
    *error = returnObject;
    return NO;
  }
  return YES;
}


#pragma mark - FBDeviceOperator protocol

- (BOOL)waitForDeviceToBecomeAvailableWithError:(NSError **)error
{
  if (![[[[[FBRunLoopSpinner new]
           timeout:5 * 60]
          timeoutErrorMessage:@"Device was locked"]
         reminderMessage:@"Please unlock device!"]
        spinUntilTrue:^BOOL{ return ![self.dvtDevice isPasscodeLocked]; } error:error])
  {
    return NO;
  }

  if (![[[[[FBRunLoopSpinner new]
           timeout:5 * 60]
          timeoutErrorMessage:@"Device did not become available"]
         reminderMessage:@"Waiting for device to become available!"]
        spinUntilTrue:^BOOL{ return [self.dvtDevice isAvailable]; }])
  {
    return NO;
  }

  if (![[[[[FBRunLoopSpinner new]
           timeout:5 * 60]
          timeoutErrorMessage:@"Failed to gain access to device"]
         reminderMessage:@"Allow device access!"]
        spinUntilTrue:^BOOL{ return [self.iosDevice deviceReady]; } error:error])
  {
    return NO;
  }

  __block NSUInteger preLaunchLogLength;
  if (![[[[FBRunLoopSpinner new]
          timeout:60]
         timeoutErrorMessage:@"Failed to load device console entries"]
        spinUntilTrue:^BOOL{
          NSString *log = self.fullConsoleString.copy;
          if (log.length == 0) {
            return NO;
          }
          // Waiting for console to load all entries
          if (log.length != preLaunchLogLength) {
            preLaunchLogLength = log.length;
            return NO;
          }
          self.preLaunchConsoleString = log;
          return YES;
        } error:error])
  {
    return NO;
  }

  if (!self.dvtDevice.supportsXPCServiceDebugging) {
    return [[FBDeviceControlError
      describe:@"Device does not support XPC service debugging"]
      failBool:error];
  }

  if (!self.dvtDevice.serviceHubProcessControlChannel) {
    return [[FBDeviceControlError
      describe:@"Failed to create HUB control channel"]
      failBool:error];
  }
  return YES;
}

- (BOOL)installApplicationWithPath:(NSString *)path error:(NSError **)error
{
  id object = [FBRunLoopSpinner spinUntilBlockFinished:^id{
    return [self.dvtDevice installApplicationSync:path options:nil];
  }];
  if ([object isKindOfClass:NSError.class]) {
    if (error) {
      *error = object;
    }
    return NO;
  };
  return YES;
}

- (BOOL)isApplicationInstalledWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return [self installedApplicationWithBundleIdentifier:bundleID] != nil;
}

- (BOOL)launchApplicationWithBundleID:(NSString *)bundleID arguments:(NSArray *)arguments environment:(NSDictionary *)environment error:(NSError **)error
{
  NSAssert(error, @"error is required for hub commands");
  NSString *remotePath = [self applicationPathForApplicationWithBundleID:bundleID error:error];
  NSDictionary *options = @{@"StartSuspendedKey" : @NO};
  SEL aSelector = NSSelectorFromString(@"launchSuspendedProcessWithDevicePath:bundleIdentifier:environment:arguments:options:");
  NSNumber *PID =
  [self executeHubProcessControlSelector:aSelector
                                   error:error
                               arguments:remotePath, bundleID, environment, arguments, options, nil];
  if (!PID) {
    return NO;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    [self observeProcessWithID:PID.integerValue error:error];
  });
  return YES;
}

- (pid_t)processIDWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSAssert(error, @"error is required for hub commands");
  return
  [[self executeHubProcessControlSelector:NSSelectorFromString(@"processIdentifierForBundleIdentifier:")
                                    error:error
                                arguments:bundleID, nil]
   intValue];
}

- (BOOL)killApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  pid_t PID = [self processIDWithBundleID:bundleID error:error];
  if (!PID) {
    return NO;
  }
  return [self killProcessWithID:PID error:error];
}

- (NSString *)fullConsoleString
{
  return [self.iosDevice.token.deviceConsoleController consoleString];
}

- (NSString *)consoleString
{
  NSString *consoleString = self.fullConsoleString.copy;
  if (consoleString.length == 0) {
    return nil;
  }
  NSString *markerString = [FBSubstringUtilities substringOf:self.preLaunchConsoleString withLastCharacterCount:FBMaxConosleMarkerLength];
  return [FBSubstringUtilities substringAfterNeedle:markerString inHaystack:consoleString];
}


- (BOOL)observeProcessWithID:(NSInteger)processID error:(NSError **)error
{
  NSAssert(error, @"error is required for hub commands");
  [self executeHubProcessControlSelector:NSSelectorFromString(@"startObservingPid:")
                                   error:error
                               arguments:@(processID), nil];
  return (*error == nil);
}

- (BOOL)killProcessWithID:(NSInteger)processID error:(NSError **)error
{
  NSAssert(error, @"error is required for hub commands");
  [self executeHubProcessControlSelector:NSSelectorFromString(@"killPid:")
                                   error:error
                               arguments:@(processID), nil];
  return (*error == nil);
}


#pragma mark - Helpers

- (id)executeHubProcessControlSelector:(SEL)aSelector error:(NSError **)error arguments:(id)arg, ...
{
  NSAssert(error, @"error is required for hub commands");
  va_list _arguments;
  va_start(_arguments, arg);
  va_list *arguments = &_arguments;
  return
  [FBRunLoopSpinner spinUntilBlockFinished:^id{
    __block id responseObject;
    DTXChannel *channel = self.dvtDevice.serviceHubProcessControlChannel;
    DTXMessage *message = [[NSClassFromString(@"DTXMessage") alloc] initWithSelector:aSelector firstArg:arg remainingObjectArgs:(__bridge id)(*arguments)];
    [channel sendControlSync:message replyHandler:^(DTXMessage *responseMessage){
      if (responseMessage.errorStatus) {
        *error = responseMessage.error;
        return;
      }
      responseObject = responseMessage.object;
    }];
    return responseObject;
  }];
  va_end(_arguments);
}

@end

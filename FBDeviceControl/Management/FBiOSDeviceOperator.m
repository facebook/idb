/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBiOSDeviceOperator.h"

#import <objc/runtime.h>

#import <DTDeviceKitBase/DTDKRemoteDeviceConsoleController.h>
#import <DTDeviceKitBase/DTDKRemoteDeviceToken.h>

#import <DTXConnectionServices/DTXChannel.h>
#import <DTXConnectionServices/DTXMessage.h>
#import <DTXConnectionServices/DTXSocketTransport.h>

#import <DVTFoundation/DVTDeviceManager.h>
#import <DVTFoundation/DVTFuture.h>

#import <IDEiOSSupportCore/DVTiOSDevice.h>

#import <FBControlCore/FBControlCore.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import <objc/runtime.h>

#import "FBDevice.h"
#import "FBDevice+Private.h"
#import "FBDeviceSet.h"
#import "FBAMDevice+Private.h"
#import "FBDeviceControlError.h"
#import "FBDeviceControlFrameworkLoader.h"

#import "FBiOSDeviceReadynessStrategy.h"

#import <FBControlCore/FBControlCore.h>

@protocol DVTApplication <NSObject>
- (NSString *)installedPath;
- (NSString *)containerPath;
- (NSString *)identifier;
- (NSString *)executableName;
@end

@interface FBiOSDeviceOperator ()

@property (nonatomic, strong, readonly) FBDevice *device;

// The DVTDevice corresponding to the receiver.
@property (nonatomic, nullable, strong, readonly) DVTiOSDevice *dvtDevice;

@end

@implementation FBiOSDeviceOperator

@synthesize dvtDevice = _dvtDevice;
- (DVTiOSDevice *)dvtDevice
{
  if (_dvtDevice == nil) {
    _dvtDevice = [self dvtDeviceWithUDID:self.udid];
  }
  return _dvtDevice;
}

+ (instancetype)forDevice:(FBDevice *)device
{
  return [[self alloc] initWithDevice:device];
}

- (instancetype)initWithDevice:(FBDevice *)device;
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;

  return self;
}

- (NSString *)udid
{
  return self.device.udid;
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

- (void)fetchApplications
{
  [[self fetchApplicationsAsync] await:nil];
}

- (id<DVTApplication>)installedApplicationWithBundleIdentifier:(NSString *)bundleID
{
  [self fetchApplications];
  return [self.dvtDevice installedApplicationWithBundleIdentifier:bundleID];
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
   buildWithError:error];

  return productBundle;
}

- (BOOL)uploadApplicationDataAtPath:(NSString *)path bundleID:(NSString *)bundleID error:(NSError **)error
{
  return [[[self uploadApplicationDataAtPath:path bundleID:bundleID] await:error] boolValue];
}

- (FBFuture<NSNumber *> *)uploadApplicationDataAtPath:(NSString *)path bundleID:(NSString *)bundleID
{
  return [FBFuture onQueue:self.device.asyncQueue resolveValue:^id (NSError **error) {
    BOOL result = [self.dvtDevice uploadApplicationDataWithPath:path forInstalledApplicationWithBundleIdentifier:bundleID error:error];
    return result ? @(result) : nil;
  }];
}

- (BOOL)cleanApplicationStateWithBundleIdentifier:(NSString *)bundleIdentifier error:(NSError **)error
{
  return [[self cleanApplicationStateWithBundleIdentifier:bundleIdentifier] await:error] != nil;
}

#pragma mark - DVTDevice support

- (nullable DVTiOSDevice *)dvtDeviceWithUDID:(NSString *)udid
{
  [self primeDVTDeviceManager];
  NSDictionary<NSString *, DVTiOSDevice *> *dvtDevices = [[self class] keyDVTDevicesByUDID:[objc_lookUpClass("DVTiOSDevice") alliOSDevices]];
  return dvtDevices[udid];
}

+ (NSDictionary<NSString *, DVTiOSDevice *> *)keyDVTDevicesByUDID:(NSArray<DVTiOSDevice *> *)devices
{
  NSMutableDictionary<NSString *, DVTiOSDevice *> *dictionary = [NSMutableDictionary dictionary];
  for (DVTiOSDevice *device in devices) {
    dictionary[device.identifier] = device;
  }
  return [dictionary copy];
}

static const NSTimeInterval FBiOSDeviceOperatorDVTDeviceManagerTickleTime = 2;
- (void)primeDVTDeviceManager
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    // It seems that searching for a device that does not exist will cause all available devices/simulators etc. to be cached.
    // There's probably a better way of fetching all the available devices, but this appears to work well enough.
    // This means that all the cached available devices can then be found.
    [FBDeviceControlFrameworkLoader.xcodeFrameworks loadPrivateFrameworksOrAbort];

    DVTDeviceManager *deviceManager = [objc_lookUpClass("DVTDeviceManager") defaultDeviceManager];
    [deviceManager searchForDevicesWithType:nil options:@{@"id" : @"I_DONT_EXIST_AT_ALL"} timeout:FBiOSDeviceOperatorDVTDeviceManagerTickleTime error:nil];
  });
}

#pragma mark - FBDeviceOperator protocol

- (DTXTransport *)makeTransportForTestManagerServiceWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if ([NSThread isMainThread]) {
    return
    [[[FBDeviceControlError
       describe:@"'makeTransportForTestManagerService' method may block and should not be called on the main thread"]
      logger:logger]
     fail:error];
  }
  NSError *innerError;
  CFTypeRef connection = [self.device.amDevice startTestManagerServiceWithError:&innerError];
  if (!connection) {
    return
    [[[[FBDeviceControlError
        describe:@"Failed to start test manager daemon service."]
       logger:logger]
      causedBy:innerError]
     fail:error];
  }
  int socket = FBAMDServiceConnectionGetSocket(connection);
  if (socket <= 0) {
    return
    [[[FBDeviceControlError
       describe:@"Invalid socket returned from AMDServiceConnectionGetSocket"]
      logger:logger]
     fail:error];
  }
  return
  [[objc_lookUpClass("DTXSocketTransport") alloc] initWithConnectedSocket:socket disconnectAction:^{
    [logger log:@"Disconnected from test manager daemon socket"];
    FBAMDServiceConnectionInvalidate(connection);
  }];
}

- (BOOL)requiresTestDaemonMediationForTestHostConnection
{
  return self.dvtDevice.requiresTestDaemonMediationForTestHostConnection;
}

- (BOOL)waitForDeviceToBecomeAvailableWithError:(NSError **)error
{
  FBiOSDeviceReadynessStrategy *strategy = [FBiOSDeviceReadynessStrategy strategyWithDVTDevice:self.dvtDevice workQueue:self.device.workQueue];
  return [[[strategy waitForDeviceReadyToDebug] timedOutIn:4 * 60] await:error] != nil;
}

- (FBFuture<id> *)processIDWithBundleID:(NSString *)bundleID
{
  return [self
    hubControlFutureWithSelector:NSSelectorFromString(@"processIdentifierForBundleIdentifier:")
    arg:bundleID, nil];
}

- (nullable FBDiagnostic *)attemptToFindCrashLogForProcess:(pid_t)pid bundleID:(NSString *)bundleID sinceDate:(NSDate *)date
{
  return nil;
}

- (NSString *)consoleString
{
  return [self.dvtDevice.token.deviceConsoleController consoleString];
}

- (FBFuture<id> *)observeProcessWithID:(pid_t)processID
{
  return [self
    hubControlFutureWithSelector:NSSelectorFromString(@"startObservingPid:")
    arg:@(processID), nil];
}

- (FBFuture<id> *)killProcessWithID:(pid_t)processID
{
  return [self
    hubControlFutureWithSelector:NSSelectorFromString(@"killPid:")
    arg:@(processID), nil];
}

#pragma mark FBApplicationCommands Implementation

- (FBFuture<NSNumber *> *)isApplicationInstalledWithBundleID:(NSString *)bundleID
{
  return [self installedApplicationWithBundleIdentifier:bundleID];
}

- (FBFuture<id> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration
{
  NSError *error = nil;
  NSString *remotePath = [self applicationPathForApplicationWithBundleID:configuration.bundleID error:&error];
  if (!remotePath) {
    return [FBFuture futureWithError:error];
  }
  NSDictionary *options = @{@"StartSuspendedKey" : @NO};
  return [[self
    hubControlFutureWithSelector:NSSelectorFromString(@"launchSuspendedProcessWithDevicePath:bundleIdentifier:environment:arguments:options:")
    arg:remotePath, configuration.bundleID, configuration.environment, configuration.arguments, options, nil]
    onQueue:dispatch_get_main_queue() fmap:^(NSNumber *processIdentifier) {
      return [self observeProcessWithID:processIdentifier.intValue];
    }];
}

- (FBFuture<NSNull *> *)killApplicationWithBundleID:(NSString *)bundleID
{
  return [[self
    processIDWithBundleID:bundleID]
    onQueue:dispatch_get_main_queue() fmap:^FBFuture *(NSNumber *processIdentifier) {
      return [self killProcessWithID:processIdentifier.intValue];
    }];
}

#pragma mark - Helpers

- (FBFuture<id> *)hubControlFutureWithSelector:(SEL)selector arg:(id)arg, ...
{
  va_list arguments;
  va_start(arguments, arg);

  FBMutableFuture<id> *future = FBMutableFuture.future;
  DTXChannel *channel = self.dvtDevice.serviceHubProcessControlChannel;
  DTXMessage *message = [[objc_lookUpClass("DTXMessage") alloc] initWithSelector:selector firstArg:arg remainingObjectArgs:(__bridge id)arguments];
  va_end(arguments);

  [channel sendMessageAsync:message replyHandler:^(DTXMessage *responseMessage) {
    if (responseMessage.errorStatus) {
      [future resolveWithError:responseMessage.error];
    } else {
      [future resolveWithResult:responseMessage.object];
    }
  }];

  return future;
}

- (id)executeHubProcessControlSelector:(SEL)aSelector
                                 error:(NSError *_Nullable *)error
                             arguments:(id)arg, ...
{
  return [[self hubControlFutureWithSelector:aSelector arg:arg] await:error];
}

- (FBFuture<NSNull *> *)fetchApplicationsAsync
{
  if (!self.dvtDevice.applications) {
    return [FBFuture onQueue:self.device.asyncQueue resolveValue:^id (NSError **error) {
      DVTFuture *future = [self.dvtDevice.token fetchApplications];
      [future waitUntilFinished];
      return NSNull.null;
    }];
  } else {
    return [FBFuture futureWithResult:NSNull.null];
  }
}

- (FBFuture<id> *)cleanApplicationStateWithBundleIdentifier:(NSString *)bundleIdentifier
{
  return [FBFuture onQueue:self.device.asyncQueue resolveValue:^id (NSError **error) {
    if ([self.dvtDevice installedApplicationWithBundleIdentifier:bundleIdentifier]) {
      return [self.dvtDevice uninstallApplicationWithBundleIdentifierSync:bundleIdentifier];
    } else {
      return @YES;
    }
  }];
}

@end

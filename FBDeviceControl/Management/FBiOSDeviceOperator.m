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

#import "FBAFCConnection.h"
#import "FBAMDServiceConnection.h"
#import "FBAMDevice+Private.h"
#import "FBDevice+Private.h"
#import "FBDevice.h"
#import "FBDeviceControlError.h"
#import "FBDeviceControlFrameworkLoader.h"
#import "FBDeviceSet.h"

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
    _dvtDevice = [self dvtDeviceWithUDID:self.device.udid];
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

- (FBFuture<DTXTransport *> *)makeTransportForTestManagerServiceWithLogger:(id<FBControlCoreLogger>)logger
{
  if ([NSThread isMainThread]) {
    return [[[FBDeviceControlError
      describe:@"'makeTransportForTestManagerService' method may block and should not be called on the main thread"]
      logger:logger]
      failFuture];
  }

  return [[self.device.amDevice
    startTestManagerService]
    onQueue:self.device.workQueue pop:^(FBAMDServiceConnection *connection) {
      int socket = connection.socket;
      if (socket <= 0) {
        return [[[FBDeviceControlError
          describe:@"Invalid socket returned from AMDServiceConnectionGetSocket"]
          logger:logger]
          failFuture];
      }
      DTXTransport *transport = [[objc_lookUpClass("DTXSocketTransport") alloc] initWithConnectedSocket:socket disconnectAction:^{
        [logger log:@"Disconnected from test manager daemon socket"];
      }];
      return [FBFuture futureWithResult:transport];
    }];
}

- (BOOL)requiresTestDaemonMediationForTestHostConnection
{
  return self.dvtDevice.requiresTestDaemonMediationForTestHostConnection;
}

- (FBFuture<id> *)processIDWithBundleID:(NSString *)bundleID
{
  return [self
    hubControlFutureWithSelector:NSSelectorFromString(@"processIdentifierForBundleIdentifier:")
    arg:bundleID, nil];
}

- (FBFuture<id> *)killProcessWithID:(pid_t)processID
{
  return [self
    hubControlFutureWithSelector:NSSelectorFromString(@"killPid:")
    arg:@(processID), nil];
}

#pragma mark FBApplicationCommands Implementation

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

@end

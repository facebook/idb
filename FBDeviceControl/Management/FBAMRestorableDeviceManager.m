/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAMRestorableDeviceManager.h"

#import "FBDeviceControlError.h"
#import "FBDeviceControlFrameworkLoader.h"
#import "FBAMRestorableDevice.h"

@interface FBAMRestorableDeviceManager ()

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, assign, readonly) AMDCalls calls;
@property (nonatomic, assign, readwrite) int registrationID;
@property (nonatomic, copy, readonly) NSString *ecidFilter;

- (NSDictionary<NSString *, id> *)infoForRestorableDevice:(AMRestorableDeviceRef)device;

@end

static NSString *NotificationTypeToString(AMRestorableDeviceNotificationType status)
{
  switch (status) {
    case AMRestorableDeviceNotificationTypeConnected:
      return @"connected";
    case AMRestorableDeviceNotificationTypeDisconnected:
      return @"disconnected";
    default:
      return @"unknown";
  }
}

static void FB_AMRestorableDeviceListenerCallback(AMRestorableDeviceRef device, AMRestorableDeviceNotificationType status, void *context)
{
  FBAMRestorableDeviceManager *manager = (__bridge FBAMRestorableDeviceManager *)context;
  id<FBControlCoreLogger> logger = manager.logger;
  AMRestorableDeviceState deviceState = manager.calls.RestorableDeviceGetState(device);
  FBiOSTargetState targetState = [FBAMRestorableDevice targetStateForDeviceState:deviceState];
  NSString *identifier = [@(manager.calls.RestorableDeviceGetECID(device)) stringValue];
  [logger logFormat:@"%@ %@ in state %@", device, NotificationTypeToString(status), FBiOSTargetStateStringFromState(targetState)];
  if (manager.ecidFilter && ![identifier isEqualToString:manager.ecidFilter]) {
    [logger logFormat:@"Ignoring %@ as it does not match filter of %@", device, manager.ecidFilter];
    return;
  }
  switch (status) {
    case AMRestorableDeviceNotificationTypeConnected: {
      NSDictionary<NSString *, id> *info = [manager infoForRestorableDevice:device];
      [logger logFormat:@"Caching restorable device values %@", info];
      [manager deviceConnected:device identifier:identifier info:info];
      return;
    }
    case AMRestorableDeviceNotificationTypeDisconnected:
      [manager deviceDisconnected:device identifier:identifier];
      return;
    default:
      [logger logFormat:@"Unknown Restorable Notification %d", status];
      return;
  }
}

@implementation FBAMRestorableDeviceManager

#pragma mark Initializers

- (instancetype)initWithCalls:(AMDCalls)calls queue:(dispatch_queue_t)queue ecidFilter:(NSString *)ecidFilter logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithLogger:logger];
  if (!self) {
    return nil;
  }

  _calls = calls;
  _queue = queue;
  _ecidFilter = ecidFilter;

  return self;
}

#pragma mark Abstract Implementation

- (BOOL)startListeningWithError:(NSError **)error
{
  int registrationID = self.calls.RestorableDeviceRegisterForNotifications(
    FB_AMRestorableDeviceListenerCallback,
    (void *) CFBridgingRetain(self),
    0,
    0
  );
  if (registrationID < 1) {
    return [[FBDeviceControlError
      describeFormat:@"AMRestorableDeviceRegisterForNotifications failed with %d", registrationID]
      failBool:error];
  }
  self.registrationID = registrationID;
  return YES;
}

- (BOOL)stopListeningWithError:(NSError **)error
{
  int registrationID = self.registrationID;
  self.registrationID = 0;
  if (registrationID < 1) {
    return [[FBDeviceControlError
      describe:@"Cannot unregister from AMRestorableDevice notifications, no subscription"]
      failBool:error];
  }

  // Return of AMRestorableDeviceUnregisterForNotifications seems to be some random number.
  // However, giving invalid registrationID is fine and we still get logging.
  self.calls.RestorableDeviceUnregisterForNotifications(registrationID);
  return YES;
}

- (FBAMRestorableDevice *)constructPublic:(AMRestorableDeviceRef)privateDevice identifier:(NSString *)identifier info:(NSDictionary<NSString *,id> *)info
{
  return [[FBAMRestorableDevice alloc] initWithCalls:self.calls restorableDevice:privateDevice allValues:info logger:[self.logger withName:identifier]];
}

+ (void)updatePublicReference:(FBAMRestorableDevice *)publicDevice privateDevice:(AMRestorableDeviceRef)privateDevice identifier:(NSString *)identifier info:(NSDictionary<NSString *,id> *)info
{
  publicDevice.restorableDevice = privateDevice;
  publicDevice.allValues = info;
}

+ (AMRestorableDeviceRef)extractPrivateReference:(FBAMRestorableDevice *)publicDevice
{
  return publicDevice.restorableDevice;
}

- (NSDictionary<NSString *, id> *)infoForRestorableDevice:(AMRestorableDeviceRef)device
{
  return @{
    FBDeviceKeyChipID: @(self.calls.RestorableDeviceGetChipID(device)),
    FBDeviceKeyDeviceClass: @(self.calls.RestorableDeviceGetDeviceClass(device)),
    FBDeviceKeyLocationID: @(self.calls.RestorableDeviceGetLocationID(device)),
    FBDeviceKeySerialNumber: CFBridgingRelease(self.calls.RestorableDeviceCopySerialNumber(device)) ?: NSNull.null,
    FBDeviceKeyDeviceName: CFBridgingRelease(self.calls.RestorableDeviceCopyUserFriendlyName(device)) ?: NSNull.null,
    FBDeviceKeyProductType: CFBridgingRelease(self.calls.RestorableDeviceCopyProductString(device)) ?: NSNull.null,
    FBDeviceKeyUniqueChipID: @(self.calls.RestorableDeviceGetECID(device)),
  };
}

@end

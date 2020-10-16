/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAMDeviceManager.h"

#import "FBAMDevice+Private.h"
#import "FBAMRestorableDevice.h"
#import "FBDeviceControlError.h"
#import "FBDeviceControlFrameworkLoader.h"

static NSString *const MobileBackupDomain = @"com.apple.mobile.backup";

@interface FBAMDeviceManager ()

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, assign, readonly) AMDCalls calls;
@property (nonatomic, copy, nullable, readonly) NSString *ecidFilter;
@property (nonatomic, assign, readwrite) AMDNotificationSubscription subscription;

- (NSString *)identifierForDevice:(AMDeviceRef)device;

@end

static BOOL FB_AMDeviceConnected(AMDeviceRef device, FBAMDeviceManager *manager)
{
  NSError *error = nil;
  id<FBControlCoreLogger> logger = manager.logger;
  AMDCalls calls = manager.calls;
  if (![FBAMDeviceManager startUsing:device calls:calls logger:logger error:&error]) {
    [logger.error logFormat:@"Cannot start session with device, ignoring device %@", error];
    return NO;
  }
  NSString *uniqueChipID = [CFBridgingRelease(calls.CopyValue(device, NULL, (__bridge CFStringRef)(FBDeviceKeyUniqueChipID))) stringValue];
  if (!uniqueChipID) {
    [FBAMDeviceManager stopUsing:device calls:calls logger:logger error:nil];
    [logger.error logFormat:@"Ignoring device as cannot obtain ECID for it"];
    return NO;
  }
  if (manager.ecidFilter && ![uniqueChipID isEqualToString:manager.ecidFilter]) {
    [FBAMDeviceManager stopUsing:device calls:calls logger:logger error:nil];
    [logger.error logFormat:@"Ignoring device as ECID %@ does not match filter %@", uniqueChipID, manager.ecidFilter];
    return NO;
  }
  // Get the values from the default domain.
  NSMutableDictionary<NSString *, id> *info = [CFBridgingRelease(calls.CopyValue(device, NULL, NULL)) mutableCopy];
  // Get values from mobile backup.
  NSDictionary<NSString *, id> * backupInfo = [CFBridgingRelease(calls.CopyValue(device, (__bridge CFStringRef)(MobileBackupDomain), NULL)) copy] ?: @{};
  // We're done with getting the device values.
  [FBAMDeviceManager stopUsing:device calls:calls logger:logger error:nil];
  if (!info) {
    [logger.error log:@"Ignoring device as no values were returned for it"];
    return NO;
  }
  // Insert the values from subdomains.
  info[MobileBackupDomain] = backupInfo;
  NSString *udid = info[FBDeviceKeyUniqueDeviceID];
  if (!udid) {
    [logger.error logFormat:@"Ignoring device as %@ is not present in %@", FBDeviceKeyUniqueDeviceID, info];
    return NO;
  }
  [logger.debug logFormat:@"Obtained Device Values %@", info];
  [manager deviceConnected:device identifier:uniqueChipID info:info];
  return YES;
}

static void FB_AMDeviceListenerCallback(AMDeviceNotification *notification, FBAMDeviceManager *manager)
{
  AMDeviceNotificationType notificationType = notification->status;
  AMDeviceRef device = notification->amDevice;
  id<FBControlCoreLogger> logger = manager.logger;
  switch (notificationType) {
    case AMDeviceNotificationTypeConnected:
    case AMDeviceNotificationTypePaired:
      FB_AMDeviceConnected(device, manager);
      return;
    case AMDeviceNotificationTypeDisconnected: {
      NSString *identifier = [manager identifierForDevice:device];
      if (!identifier) {
        [logger logFormat:@"Cannot obtain identifier for device %@", device];
        return;
      }
      [manager deviceDisconnected:device identifier:[manager identifierForDevice:device]];
      return;
    }
    case AMDeviceNotificationTypeUnsubscribed:
      [logger logFormat:@"Unsubscribed from AMDeviceNotificationSubscribe"];
      return;
    default:
      [manager.logger logFormat:@"Got Unknown status %d from AMDeviceNotificationSubscribe", notificationType];
      return;
  }
}

@implementation FBAMDeviceManager

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

#pragma mark Public

+ (BOOL)startUsing:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if (device == NULL) {
    return [[FBDeviceControlError
      describe:@"Cannot utilize a non existent AMDeviceRef"]
      failBool:error];
  }

  [logger logFormat:@"Connecting to %@", device];
  int status = calls.Connect(device);
  if (status != 0) {
    NSString *errorDescription = CFBridgingRelease(calls.CopyErrorText(status));
    return [[FBDeviceControlError
      describeFormat:@"Failed to connect to %@. (%@)", device, errorDescription]
      failBool:error];
  }

  [logger logFormat:@"Checking whether %@ is paired", device];
  if (!calls.IsPaired(device)) {
    [logger logFormat:@"%@ is not paired, attempting to pair", device];
    status = calls.Pair(device);
    if (status != 0) {
      NSString *errorDescription = CFBridgingRelease(calls.CopyErrorText(status));
      return [[FBDeviceControlError
        describeFormat:@"%@ is not paired with this host %@", device, errorDescription]
        failBool:error];
    }
    [logger logFormat:@"%@ succeeded pairing request", device];
  }

  [logger logFormat:@"Validating Pairing to %@", device];
  status = calls.ValidatePairing(device);
  if (status != 0) {
    NSString *errorDescription = CFBridgingRelease(calls.CopyErrorText(status));
    return [[FBDeviceControlError
      describeFormat:@"Failed to validate pairing for %@. (%@)", device, errorDescription]
      failBool:error];
  }

  [logger logFormat:@"Starting Session on %@", device];
  status = calls.StartSession(device);
  if (status != 0) {
    calls.Disconnect(device);
    NSString *errorDescription = CFBridgingRelease(calls.CopyErrorText(status));
    return [[FBDeviceControlError
      describeFormat:@"Failed to start session with device. (%@)", errorDescription]
      failBool:error];
  }

  [logger logFormat:@"%@ ready for use", device];
  return YES;
}

+ (BOOL)stopUsing:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  [logger logFormat:@"Stopping Session on %@", device];
  calls.StopSession(device);

  [logger logFormat:@"Disconnecting from %@", device];
  calls.Disconnect(device);

  [logger logFormat:@"Disconnected from %@", device];

  return YES;
}

#pragma mark FBDeviceManager Implementation

- (BOOL)startListeningWithError:(NSError **)error
{
  if (self.subscription) {
    return [[FBDeviceControlError
      describe:@"An AMDeviceNotification Subscription already exists"]
      failBool:error];
  }

  // Perform a bridging retain, so that the context of the callback can be strongly referenced.
  // Tidied up when unsubscribing.
  AMDNotificationSubscription subscription = nil;
  int result = self.calls.NotificationSubscribe(
    (AMDeviceNotificationCallback) FB_AMDeviceListenerCallback,
    0,
    0,
    (void *) CFBridgingRetain(self),
    &subscription
  );
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"AMDeviceNotificationSubscribe failed with %d", result]
      failBool:error];
  }

  self.subscription = subscription;
  return YES;
}

- (BOOL)stopListeningWithError:(NSError **)error
{
  if (!self.subscription) {
    return [[FBDeviceControlError
      describe:@"An AMDeviceNotification Subscription does not exist"]
      failBool:error];
  }

  int result = self.calls.NotificationUnsubscribe(self.subscription);
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"AMDeviceNotificationUnsubscribe failed with %d", result]
      failBool:error];
  }

  // Cleanup after the subscription.
  CFRelease((__bridge CFTypeRef)(self));
  self.subscription = NULL;
  return YES;
}

static const NSTimeInterval ServiceReuseTimeout = 6.0;

- (id)constructPublic:(AMDeviceRef)privateDevice identifier:(NSString *)identifier info:(NSDictionary<NSString *,id> *)info
{
  return [[FBAMDevice alloc] initWithAllValues:info calls:self.calls connectionReuseTimeout:nil serviceReuseTimeout:@(ServiceReuseTimeout) workQueue:self.queue logger:self.logger];
}

+ (void)updatePublicReference:(FBAMDevice *)publicDevice privateDevice:(AMDeviceRef)privateDevice identifier:(NSString *)identifier info:(NSDictionary<NSString *,id> *)info
{
  publicDevice.amDeviceRef = privateDevice;
  publicDevice.allValues = info;
}

+ (AMDeviceRef)extractPrivateReference:(FBAMDevice *)publicDevice
{
  return publicDevice.amDeviceRef;
}

#pragma mark Private

- (NSString *)identifierForDevice:(AMDeviceRef)amDevice
{
  if (amDevice == NULL) {
    return nil;
  }
  for (FBAMDevice *device in self.storage.referenced.allValues) {
    if (device.amDeviceRef != amDevice) {
      continue;
    }
    return device.uniqueIdentifier;
  }
  return nil;
}

@end

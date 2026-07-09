/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAMDeviceManager.h"

#import <FBDeviceControl/FBDeviceControl-Swift.h>

#import "FBAMDevice.h"
#import "FBAMRestorableDevice.h"
#import "FBDeviceControlFrameworkLoader.h"

static NSString *const MobileBackupDomain = @"com.apple.mobile.backup";

@interface FBAMDeviceManager ()

+ (BOOL)startConnectionToDevice:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;
+ (BOOL)startSessionByPairingWithDevice:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;
+ (BOOL)stopConnectionToDevice:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;
+ (BOOL)stopSessionWithDevice:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;
+ (NSDictionary<NSString *, id> *)obtainDeviceValues:(AMDeviceRef)device calls:(AMDCalls)calls;

@property (nonatomic, readonly, strong) dispatch_queue_t workQueue;
@property (nonatomic, readonly, strong) dispatch_queue_t asyncQueue;
@property (nonatomic, readonly, assign) AMDCalls calls;
@property (nullable, nonatomic, readonly, copy) NSString *ecidFilter;
@property (nonatomic, readwrite, assign) AMDNotificationSubscription subscription;

- (NSString *)identifierForDevice:(AMDeviceRef)device;

@end

static BOOL FB_AMDeviceConnected(AMDeviceRef device, FBAMDeviceManager *manager)
{
  NSError *error = nil;
  id<FBControlCoreLogger> logger = manager.logger;
  AMDCalls calls = manager.calls;

  // Start with a basic connection. This should always succeed, even if the device is not paired.
  if (![FBAMDeviceManager startConnectionToDevice:device calls:calls logger:logger error:&error]) {
    [logger.error log:[NSString stringWithFormat:@"Cannot connect to device, ignoring device %@", error]];
    return NO;
  }
  NSString *uniqueChipID = [CFBridgingRelease(calls.CopyValue(device, NULL, (__bridge CFStringRef)(FBDeviceKeyUniqueChipID))) stringValue];
  if (!uniqueChipID) {
    [FBAMDeviceManager stopConnectionToDevice:device calls:calls logger:logger error:nil];
    [logger.error log:@"Ignoring device as cannot obtain ECID for it"];
    return NO;
  }
  if (manager.ecidFilter && ![uniqueChipID isEqualToString:manager.ecidFilter]) {
    [FBAMDeviceManager stopConnectionToDevice:device calls:calls logger:logger error:nil];
    [logger.error log:[NSString stringWithFormat:@"Ignoring device as ECID %@ does not match filter %@", uniqueChipID, manager.ecidFilter]];
    return NO;
  }

  NSError *pairingError = nil;
  BOOL pairedWithSession = [FBAMDeviceManager startSessionByPairingWithDevice:device calls:calls logger:logger error:&pairingError];
  if (!pairedWithSession) {
    [logger log:[NSString stringWithFormat:@"Device is not paired, degraded device information will be provied %@", pairingError]];
  }

  // Now extract all of the values.
  NSDictionary<NSString *, id> *info = [FBAMDeviceManager obtainDeviceValues:device calls:calls];

  // Stop the session if one was created.
  if (pairedWithSession) {
    [FBAMDeviceManager stopSessionWithDevice:device calls:calls logger:logger error:nil];
  }
  // Always disconnect, regardless of whether there was a session or not.
  [FBAMDeviceManager stopConnectionToDevice:device calls:calls logger:logger error:nil];

  if (!info) {
    [logger.error log:@"Ignoring device as no values were returned for it"];
    return NO;
  }
  NSString *udid = info[FBDeviceKeyUniqueDeviceID];
  if (!udid) {
    [logger.error log:[NSString stringWithFormat:@"Ignoring device as %@ is not present in %@", FBDeviceKeyUniqueDeviceID, info]];
    return NO;
  }
  [logger.debug log:[NSString stringWithFormat:@"Obtained Device Values %@", info]];
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
        [logger log:[NSString stringWithFormat:@"Cannot obtain identifier for device %@", device]];
        return;
      }
      [manager deviceDisconnected:device identifier:[manager identifierForDevice:device]];
      return;
    }
    case AMDeviceNotificationTypeUnsubscribed:
      [logger log:@"Unsubscribed from AMDeviceNotificationSubscribe"];
      return;
    default:
      [manager.logger log:[NSString stringWithFormat:@"Got Unknown status %d from AMDeviceNotificationSubscribe", notificationType]];
      return;
  }
}

@implementation FBAMDeviceManager

#pragma mark Initializers

- (instancetype)initWithCalls:(AMDCalls)calls workQueue:(dispatch_queue_t)workQueue asyncQueue:(dispatch_queue_t)asyncQueue ecidFilter:(NSString *)ecidFilter logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithLogger:logger];
  if (!self) {
    return nil;
  }

  _calls = calls;
  _workQueue = workQueue;
  _asyncQueue = asyncQueue;
  _ecidFilter = ecidFilter;

  return self;
}

#pragma mark Public

+ (BOOL)startUsing:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  // Connect first
  if (![self startConnectionToDevice:device calls:calls logger:logger error:error]) {
    return NO;
  }
  // Confirm pairing and start a session
  if (![self startSessionByPairingWithDevice:device calls:calls logger:logger error:error]) {
    return NO;
  }
  [logger log:[NSString stringWithFormat:@"%@ ready for use", device]];
  return YES;
}

+ (BOOL)stopUsing:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  // Stop the session first.
  [self stopSessionWithDevice:device calls:calls logger:logger error:nil];

  // Then the connection.
  [self stopConnectionToDevice:device calls:calls logger:logger error:nil];

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
             describe:[NSString stringWithFormat:@"AMDeviceNotificationSubscribe failed with %d", result]]
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
             describe:[NSString stringWithFormat:@"AMDeviceNotificationUnsubscribe failed with %d", result]]
            failBool:error];
  }

  // Cleanup after the subscription.
  CFRelease((__bridge CFTypeRef)(self));
  self.subscription = NULL;
  return YES;
}

static const NSTimeInterval ServiceReuseTimeout = 6.0;

- (id)constructPublic:(AMDeviceRef)privateDevice identifier:(NSString *)identifier info:(NSDictionary<NSString *, id> *)info
{
  return [[FBAMDevice alloc] initWithAllValues:info
                                         calls:self.calls
                        connectionReuseTimeout:nil
                           serviceReuseTimeout:@(ServiceReuseTimeout)
                                     workQueue:self.workQueue
                                    asyncQueue:self.asyncQueue
                                        logger:self.logger];
}

+ (void)updatePublicReference:(FBAMDevice *)publicDevice privateDevice:(AMDeviceRef)privateDevice identifier:(NSString *)identifier info:(NSDictionary<NSString *, id> *)info
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

+ (BOOL)startConnectionToDevice:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if (device == NULL) {
    return [[FBDeviceControlError
             describe:@"Cannot utilize a non existent AMDeviceRef"]
            failBool:error];
  }

  [logger log:[NSString stringWithFormat:@"Connecting to %@", device]];
  int status = calls.Connect(device);
  if (status != 0) {
    NSString *errorDescription = CFBridgingRelease(calls.CopyErrorText(status));
    return [[FBDeviceControlError
             describe:[NSString stringWithFormat:@"Failed to connect to %@. (%@)", device, errorDescription]]
            failBool:error];
  }
  return YES;
}

+ (BOOL)startSessionByPairingWithDevice:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  // Then confirm the pairing.
  [logger log:[NSString stringWithFormat:@"Checking whether %@ is paired", device]];
  if (!calls.IsPaired(device)) {
    [logger log:[NSString stringWithFormat:@"%@ is not paired, attempting to pair", device]];
    int status = calls.Pair(device);
    if (status != 0) {
      NSString *errorDescription = CFBridgingRelease(calls.CopyErrorText(status));
      return [[FBDeviceControlError
               describe:[NSString stringWithFormat:@"%@ is not paired with this host %@", device, errorDescription]]
              failBool:error];
    }
    [logger log:[NSString stringWithFormat:@"%@ succeeded pairing request", device]];
  }

  [logger log:[NSString stringWithFormat:@"Validating Pairing to %@", device]];
  int status = calls.ValidatePairing(device);
  if (status != 0) {
    NSString *errorDescription = CFBridgingRelease(calls.CopyErrorText(status));
    return [[FBDeviceControlError
             describe:[NSString stringWithFormat:@"Failed to validate pairing for %@. (%@)", device, errorDescription]]
            failBool:error];
  }

  // A session may also be required.
  [logger log:[NSString stringWithFormat:@"Starting Session on %@", device]];
  status = calls.StartSession(device);
  if (status != 0) {
    calls.Disconnect(device);
    NSString *errorDescription = CFBridgingRelease(calls.CopyErrorText(status));
    return [[FBDeviceControlError
             describe:[NSString stringWithFormat:@"Failed to start session with device. (%@)", errorDescription]]
            failBool:error];
  }

  return YES;
}

+ (BOOL)stopSessionWithDevice:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  [logger log:[NSString stringWithFormat:@"Stopping Session on %@", device]];
  calls.StopSession(device);
  return YES;
}

+ (BOOL)stopConnectionToDevice:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  [logger log:[NSString stringWithFormat:@"Disconnecting from %@", device]];
  calls.Disconnect(device);
  [logger log:[NSString stringWithFormat:@"Disconnected from %@", device]];
  return YES;
}

+ (NSDictionary<NSString *, id> *)obtainDeviceValues:(AMDeviceRef)device calls:(AMDCalls)calls
{
  // Get the values from the default domain, this will obtain information regardless of whether pairing was successful or not.
  NSMutableDictionary<NSString *, id> *info = [CFBridgingRelease(calls.CopyValue(device, NULL, NULL)) mutableCopy];
  if (!info) {
    return nil;
  }

  // Synthetic Values.
  BOOL isPaired = calls.IsPaired(device) != 0;
  info[FBDeviceKeyIsPaired] = @(isPaired);

  // Get values from mobile backup, this will only return meaningful information if paired.
  NSDictionary<NSString *, id> *backupInfo = [CFBridgingRelease(calls.CopyValue(device, (__bridge CFStringRef)(MobileBackupDomain), NULL)) copy] ?: @{};
  // Insert the values from subdomains.
  info[MobileBackupDomain] = backupInfo;

  return info;
}

@end

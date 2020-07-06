/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAMDeviceManager.h"

#import "FBAMDevice+Private.h"
#import "FBDeviceControlError.h"
#import "FBDeviceControlFrameworkLoader.h"

@interface FBAMDeviceManager ()

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, assign, readonly) AMDCalls calls;
@property (nonatomic, assign, readwrite) AMDNotificationSubscription subscription;

- (NSString *)identifierForDevice:(AMDeviceRef)device;

@end

static BOOL FB_AMDeviceConnected(AMDeviceRef device, FBAMDeviceManager *manager)
{
  NSError *error = nil;
  id<FBControlCoreLogger> logger = manager.logger;
  NSString *identifier = [manager identifierForDevice:device];
  if (!identifier) {
    [logger.error log:@"Cannot start session with device, identifier could not be obtained %@"];
    return NO;
  }
  AMDCalls calls = manager.calls;
  if (![FBAMDeviceManager startUsing:device calls:calls logger:logger error:&error]) {
    [logger.error logFormat:@"Cannot start session with device, ignoring device %@", error];
    return NO;
  }
  NSDictionary<NSString *, id> *info = [CFBridgingRelease(calls.CopyValue(device, NULL, NULL)) copy];
  [FBAMDeviceManager stopUsing:device calls:calls logger:logger error:nil];
  if (!info) {
    [logger.error log:@"Ignoring device as no values were returned for it"];
    return NO;
  }
  [logger logFormat:@"Obtained Device Values %@", info];
  [manager deviceConnected:device identifier:identifier info:info];
  return YES;
}

static void FB_AMDeviceListenerCallback(AMDeviceNotification *notification, FBAMDeviceManager *manager)
{
  AMDeviceNotificationType notificationType = notification->status;
  AMDeviceRef device = notification->amDevice;
  id<FBControlCoreLogger> logger = manager.logger;
  switch (notificationType) {
    case AMDeviceNotificationTypeConnected:
      FB_AMDeviceConnected(device, manager);
    case AMDeviceNotificationTypeDisconnected:
      [manager deviceDisconnected:device identifier:[manager identifierForDevice:device]];
      return;
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

+ (FBAMDeviceManager *)sharedManager
{
  static dispatch_once_t onceToken;
  static FBAMDeviceManager *manager;
  dispatch_once(&onceToken, ^{
    id<FBControlCoreLogger> logger = [FBControlCoreGlobalConfiguration.defaultLogger withName:@"amdevice_manager"];
    manager = [self managerWithCalls:FBDeviceControlFrameworkLoader.amDeviceCalls queue:dispatch_get_main_queue() logger:logger];
  });
  return manager;
}

+ (FBAMDeviceManager *)managerWithCalls:(AMDCalls)calls queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  FBAMDeviceManager *manager = [[self alloc] initWithCalls:calls queue:queue logger:logger];
  NSError *error = nil;
  BOOL success = [manager startListeningWithError:&error];
  NSAssert(success, @"Failed to Start Listening %@", error);
  return manager;
}

- (instancetype)initWithCalls:(AMDCalls)calls queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithLogger:logger];
  if (!self) {
    return nil;
  }

  _queue = queue;
  _calls = calls;

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
    return [[FBDeviceControlError
      describeFormat:@"%@ is not paired with this host", device]
      failBool:error];
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

  BOOL success = [self populateFromListWithError:error];
  if (!success) {
    return NO;
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
  return [[FBAMDevice alloc] initWithUDID:identifier allValues:info calls:self.calls connectionReuseTimeout:nil serviceReuseTimeout:@(ServiceReuseTimeout) workQueue:self.queue logger:self.logger];
}

+ (void)updatePublicReference:(FBAMDevice *)publicDevice privateDevice:(AMDeviceRef)privateDevice identifier:(NSString *)identifier info:(NSDictionary<NSString *,id> *)info
{
  publicDevice.amDevice = privateDevice;
  publicDevice.allValues = info;
}

+ (AMDeviceRef)extractPrivateReference:(FBAMDevice *)publicDevice
{
  return publicDevice.amDevice;
}

#pragma mark Private

- (BOOL)populateFromListWithError:(NSError **)error
{
  [self.logger log:@"Populating devices from list"];
  _Nullable CFArrayRef array = self.calls.CreateDeviceList();
  if (array == NULL) {
    return [[FBDeviceControlError
      describe:@"AMDCreateDeviceList returned NULL"]
      failBool:error];
  }
  for (NSInteger index = 0; index < CFArrayGetCount(array); index++) {
    AMDeviceRef device = CFArrayGetValueAtIndex(array, index);
    FB_AMDeviceConnected(device, self);
  }
  CFRelease(array);
  return YES;
}

- (NSString *)identifierForDevice:(AMDeviceRef)device
{
  return CFBridgingRelease(self.calls.CopyDeviceIdentifier(device));
}

@end

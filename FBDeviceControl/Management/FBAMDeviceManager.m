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

@property (nonatomic, assign, readwrite) AMDNotificationSubscription subscription;

- (NSString *)identifierForDevice:(AMDeviceRef)device;

@end

static void FB_AMDeviceListenerCallback(AMDeviceNotification *notification, FBAMDeviceManager *manager)
{
  AMDeviceNotificationType notificationType = notification->status;
  AMDeviceRef device = notification->amDevice;
  NSString *identifier = [manager identifierForDevice:device];
  switch (notificationType) {
    case AMDeviceNotificationTypeConnected:
      [manager deviceConnected:device identifier:identifier];
      break;
    case AMDeviceNotificationTypeDisconnected:
      [manager deviceDisconnected:device identifier:identifier];
      break;
    default:
      [manager.logger logFormat:@"Got Unknown status %d from self.calls.ListenerCallback", notificationType];
      break;
  }
}

@implementation FBAMDeviceManager

#pragma mark Initializers

+ (FBAMDeviceManager *)sharedManager
{
  static dispatch_once_t onceToken;
  static FBAMDeviceManager *manager;
  dispatch_once(&onceToken, ^{
    id<FBControlCoreLogger> logger = [FBControlCoreGlobalConfiguration.defaultLogger withName:@"device_manager"];
    manager = [self managerWithCalls:FBDeviceControlFrameworkLoader.amDeviceCalls Queue:dispatch_get_main_queue() logger:logger];
  });
  return manager;
}

+ (FBAMDeviceManager *)managerWithCalls:(AMDCalls)calls Queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  FBAMDeviceManager *manager = [[self alloc] initWithCalls:calls queue:queue logger:logger];
  NSError *error = nil;
  BOOL success = [manager startListeningWithError:&error];
  NSAssert(success, @"Failed to Start Listening %@", error);
  return manager;
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

- (id)constructPublic:(AMDeviceRef)privateDevice
{
  NSString *identifier = [self identifierForDevice:privateDevice];
  return [[FBAMDevice alloc] initWithUDID:identifier calls:self.calls connectionReuseTimeout:nil serviceReuseTimeout:@(ServiceReuseTimeout) workQueue:self.queue logger:self.logger];
}

+ (void)updatePublicReference:(FBAMDevice *)publicDevice privateDevice:(AMDeviceRef)privateDevice
{
  publicDevice.amDevice = privateDevice;
}

+ (AMDeviceRef)extractPrivateReference:(FBAMDevice *)publicDevice
{
  return publicDevice.amDevice;
}

#pragma mark Private

- (BOOL)populateFromListWithError:(NSError **)error
{
  _Nullable CFArrayRef array = self.calls.CreateDeviceList();
  if (array == NULL) {
    return [[FBDeviceControlError describe:@"AMDCreateDeviceList returned NULL"] failBool:error];
  }
  for (NSInteger index = 0; index < CFArrayGetCount(array); index++) {
    AMDeviceRef value = CFArrayGetValueAtIndex(array, index);
    NSString *identifier = [self identifierForDevice:value];
    [self deviceConnected:value identifier:identifier];
  }
  CFRelease(array);
  return YES;
}

- (NSString *)identifierForDevice:(AMDeviceRef)device
{
  return CFBridgingRelease(self.calls.CopyDeviceIdentifier(device));
}

@end

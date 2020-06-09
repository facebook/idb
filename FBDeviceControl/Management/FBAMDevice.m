/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAMDevice.h"
#import "FBAMDevice+Private.h"

#import <FBControlCore/FBControlCore.h>

#include <dlfcn.h>

#import "FBAFCConnection.h"
#import "FBAMDeviceServiceManager.h"
#import "FBAMDServiceConnection.h"
#import "FBDeviceControlError.h"
#import "FBDeviceControlFrameworkLoader.h"

#pragma mark - Notifications

NSNotificationName const FBAMDeviceNotificationNameDeviceAttached = @"FBAMDeviceNotificationNameDeviceAttached";

NSNotificationName const FBAMDeviceNotificationNameDeviceDetached = @"FBAMDeviceNotificationNameDeviceDetached";

#pragma mark - FBAMDeviceListener

@interface FBAMDeviceManager : NSObject

@property (nonatomic, assign, readonly) AMDCalls calls;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, FBAMDevice *> *attachedDevices;
@property (nonatomic, strong, readonly) NSMapTable<NSString *, FBAMDevice *> *referencedDevices;

@property (nonatomic, assign, readwrite) AMDNotificationSubscription subscription;

- (void)deviceConnected:(AMDeviceRef)amDevice;
- (void)deviceDisconnected:(AMDeviceRef)amDevice;

@end

static void FB_AMDeviceListenerCallback(AMDeviceNotification *notification, FBAMDeviceManager *manager)
{
  AMDeviceNotificationType notificationType = notification->status;
  switch (notificationType) {
    case AMDeviceNotificationTypeConnected:
      [manager deviceConnected:notification->amDevice];
      break;
    case AMDeviceNotificationTypeDisconnected:
      [manager deviceDisconnected:notification->amDevice];
      break;
    default:
      [manager.logger logFormat:@"Got Unknown status %d from self.calls.ListenerCallback", notificationType];
      break;
  }
}

@implementation FBAMDeviceManager

+ (instancetype)sharedManager
{
  static dispatch_once_t onceToken;
  static FBAMDeviceManager *manager;
  dispatch_once(&onceToken, ^{
    id<FBControlCoreLogger> logger = [FBControlCoreGlobalConfiguration.defaultLogger withName:@"device_manager"];
    manager = [self managerWithCalls:FBDeviceControlFrameworkLoader.amDeviceCalls Queue:dispatch_get_main_queue() logger:logger];
  });
  return manager;
}

+ (instancetype)managerWithCalls:(AMDCalls)calls Queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  FBAMDeviceManager *manager = [[self alloc] initWithCalls:calls queue:queue logger:logger];
  NSError *error = nil;
  BOOL success = [manager populateFromListWithError:&error];
  NSAssert(success, @"Failed to list devices %@", error);
  success = [manager startListeningWithError:&error];
  NSAssert(success, @"Failed to Start Listening %@", error);
  return manager;
}

- (instancetype)initWithCalls:(AMDCalls)calls queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _calls = calls;
  _queue = queue;
  _logger = logger;
  _attachedDevices = [NSMutableDictionary dictionary];
  _referencedDevices = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsCopyIn valueOptions:NSPointerFunctionsWeakMemory];

  return self;
}

- (void)dealloc
{
  if (self.subscription) {
    [self stopListeningWithError:nil];
  }
}

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

- (BOOL)populateFromListWithError:(NSError **)error
{
  _Nullable CFArrayRef array = self.calls.CreateDeviceList();
  if (array == NULL) {
    return [[FBDeviceControlError describe:@"AMDCreateDeviceList returned NULL"] failBool:error];
  }
  for (NSInteger index = 0; index < CFArrayGetCount(array); index++) {
    AMDeviceRef value = CFArrayGetValueAtIndex(array, index);
    [self deviceConnected:value];
  }
  CFRelease(array);
  return YES;
}

static const NSTimeInterval ServiceReuseTimeout = 6.0;

- (void)deviceConnected:(AMDeviceRef)amDeviceRef
{
  [self.logger logFormat:@"Device Connected %@", amDeviceRef];
  NSString *udid = CFBridgingRelease(self.calls.CopyDeviceIdentifier(amDeviceRef));

  // Make sure that we pull from all known FBAMDevice instances.
  // We do this instead of the attached ones.
  // The reason for doing so is that consumers of FBAMDevice/FBDevice instances may be holding onto a reference to a device that's been re-connected.
  // Pulling from the map of referenced devices means that we re-use these referenced devices if they are present.
  // If the device is no-longer referenced it will have been removed from the referencedDevices mapping as it's values are weakly-held.
  FBAMDevice *device = [self.referencedDevices objectForKey:udid];
  FBAMDevice *attachedDevice = self.attachedDevices[udid];
  if (device) {
    [self.logger.info logFormat:@"Device has been re-attached %@", device];
    NSAssert(attachedDevice == nil || device == attachedDevice, @"Known referenced device %@ does not match the attached one %@!", device, attachedDevice);
  } else {
    device = [[FBAMDevice alloc] initWithUDID:udid calls:self.calls connectionReuseTimeout:nil serviceReuseTimeout:@(ServiceReuseTimeout) workQueue:self.queue logger:self.logger];
    [self.logger.info logFormat:@"Created a new FBAMDevice instance %@", device];
    NSAssert(attachedDevice == nil, @"An device is in the attached but it is not in the weak set! Attached device %@", attachedDevice);
  }
  AMDeviceRef oldDeviceRef = device.amDevice;
  if (oldDeviceRef == NULL) {
    [self.logger logFormat:@"New AMDeviceRef '%@' appeared for the first time", amDeviceRef];
    device.amDevice = amDeviceRef;
  } else if (amDeviceRef != oldDeviceRef) {
    [self.logger logFormat:@"New AMDeviceRef '%@' replaces Old Device '%@'", amDeviceRef, oldDeviceRef];
    device.amDevice = amDeviceRef;
  } else {
    [self.logger logFormat:@"Existing Device %@ is the same as the old", amDeviceRef];
  }

  // Set both the strong-memory and the weak-memory device.
  // If it already exists this is fine, otherwise it will ensure that this mapping is preserved.
  // Any removed devies will be removed from attachedDevices on disconnect so that abandoned device references are cleaned up.
  self.attachedDevices[udid] = device;
  [self.referencedDevices setObject:device forKey:udid];

  [NSNotificationCenter.defaultCenter postNotificationName:FBAMDeviceNotificationNameDeviceAttached object:device.udid];
}

- (void)deviceDisconnected:(AMDeviceRef)amDevice
{
  [self.logger logFormat:@"Device Disconnected %@", amDevice];
  NSString *udid = CFBridgingRelease(self.calls.CopyDeviceIdentifier(amDevice));
  FBAMDevice *device = self.attachedDevices[udid];
  if (!device) {
    [self.logger logFormat:@"No Device named %@ from attached devices, nothing to remove", udid];
    return;
  }
  [self.logger logFormat:@"Removing Device %@ from attached devices", udid];

  // Remove only from the list of attached devices.
  // If the device instance is not referenced elsewhere it will be removed from the referencedDevices dictionary.
  // This is because the values in that dictionary are weakly referenced.
  [self.attachedDevices removeObjectForKey:udid];
  [NSNotificationCenter.defaultCenter postNotificationName:FBAMDeviceNotificationNameDeviceDetached object:device.udid];
}

- (NSArray<FBAMDevice *> *)currentDeviceList
{
  return [self.attachedDevices.allValues sortedArrayUsingSelector:@selector(udid)];
}

@end

#pragma mark - FBAMDevice Implementation

@implementation FBAMDevice

@synthesize amDevice = _amDevice;
@synthesize udid = _udid;
@synthesize contextPoolTimeout = _contextPoolTimeout;

#pragma mark Initializers

+ (NSArray<FBAMDevice *> *)allDevices
{
  return FBAMDeviceManager.sharedManager.currentDeviceList;
}

- (instancetype)initWithUDID:(NSString *)udid calls:(AMDCalls)calls connectionReuseTimeout:(nullable NSNumber *)connectionReuseTimeout serviceReuseTimeout:(nullable NSNumber *)serviceReuseTimeout workQueue:(dispatch_queue_t)workQueue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _udid = udid;
  _calls = calls;
  _workQueue = workQueue;
  _logger = [logger withName:udid];
  _connectionContextManager = [FBFutureContextManager managerWithQueue:workQueue delegate:self logger:logger];
  _contextPoolTimeout = connectionReuseTimeout;
  _serviceManager = [FBAMDeviceServiceManager managerWithAMDevice:self serviceTimeout:serviceReuseTimeout];

  return self;
}

#pragma mark Properties

- (void)setAmDevice:(AMDeviceRef)amDevice
{
  AMDeviceRef oldAMDevice = _amDevice;
  _amDevice = amDevice;
  if (amDevice) {
    self.calls.Retain(amDevice);
  }
  if (oldAMDevice) {
    self.calls.Release(oldAMDevice);
  }
  [self cacheAllValues];
}

- (AMDeviceRef)amDevice
{
  return _amDevice;
}

- (NSDictionary<NSString *, id> *)extendedInformation
{
  NSDictionary<NSString *, id> *source = self.allValues;
  NSMutableDictionary<NSString *, id> *destination = NSMutableDictionary.dictionary;
  for (NSString *key in source.allKeys) {
    id value = source[key];
    if ([value isKindOfClass:NSString.class]) {
      destination[key] = value;
    }
    if ([value isKindOfClass:NSNumber.class]) {
      destination[key] = value;
    }
  }
  return @{@"device": destination};
}

- (NSString *)architecture
{
  return self.allValues[@"CPUArchitecture"];
}

- (NSString *)buildVersion
{
  return self.allValues[@"BuildVersion"];
}

- (NSString *)name
{
  return self.allValues[@"DeviceName"];
}

- (FBDeviceType *)deviceType
{
  return FBiOSTargetConfiguration.productTypeToDevice[self.allValues[@"ProductType"]];
}

- (FBOSVersion *)osVersion
{
  NSString *osVersion = [FBAMDevice osVersionForDeviceClass:self.allValues[@"DeviceClass"] productVersion:self.allValues[@"ProductVersion"]];
  return FBiOSTargetConfiguration.nameToOSVersion[osVersion] ?: [FBOSVersion genericWithName:osVersion];
}

- (FBiOSTargetState)state
{
  return FBiOSTargetStateBooted;
}

- (FBiOSTargetType)targetType
{
  return FBiOSTargetTypeDevice;
}

#pragma mark Public Methods

- (FBFutureContext<FBAMDevice *> *)connectToDeviceWithPurpose:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  return [self.connectionContextManager utilizeWithPurpose:string];
}

- (FBFutureContext<FBAMDServiceConnection *> *)startService:(NSString *)service
{
  NSDictionary<NSString *, id> *userInfo = @{
    @"CloseOnInvalidate" : @1,
    @"InvalidateOnDetach" : @1,
  };
  // NOTE - The pop: after connectToDeviceWithPurpose: is critical to ensure we stop the AMDevice session
  //        immediately after the service is started. See longer description in FBAMDevice.h to understand why.
  return [[[self
    connectToDeviceWithPurpose:@"start_service_%@", service]
    onQueue:self.workQueue pop:^ FBFuture *(FBAMDevice *device) {
      AMDServiceConnectionRef serviceConnection;
      [self.logger logFormat:@"Starting service %@", service];
      int status = self.calls.SecureStartService(
        device.amDevice,
        (__bridge CFStringRef)(service),
        (__bridge CFDictionaryRef)(userInfo),
        &serviceConnection
      );
      if (status != 0) {
        NSString *errorDescription = CFBridgingRelease(self.calls.CopyErrorText(status));
        return [[[FBDeviceControlError
          describeFormat:@"SecureStartService of %@ Failed with 0x%x %@", service, status, errorDescription]
          logger:self.logger]
          failFuture];
      }
      FBAMDServiceConnection *connection = [[FBAMDServiceConnection alloc] initWithServiceConnection:serviceConnection device:device.amDevice calls:self.calls logger:self.logger];
      [self.logger logFormat:@"Service %@ started", service];
      return [FBFuture futureWithResult:connection];
    }]
    onQueue:self.workQueue contextualTeardown:^(id connection, FBFutureState __) {
      [self.logger logFormat:@"Invalidating service %@", service];
      NSError *error = nil;
      if (![connection invalidateWithError:&error]) {
        [self.logger logFormat:@"Failed to invalidate service %@ with error %@", service, error];
      } else {
        [self.logger logFormat:@"Invalidated service %@", service];
      }
      return FBFuture.empty;
    }];
}

- (FBFutureContext<FBAFCConnection *> *)startAFCService
{
  return [[self
    startService:@"com.apple.afc"]
    onQueue:self.workQueue push:^(FBAMDServiceConnection *connection) {
      return [FBAFCConnection afcFromServiceConnection:connection calls:FBAFCConnection.defaultCalls logger:self.logger queue:self.workQueue];
    }];
}

- (FBFutureContext<FBAMDServiceConnection *> *)startTestManagerService
{
  // See XCTDaemonControlMobileDevice in Xcode.
  return [self startService:@"com.apple.testmanagerd.lockdown"];
}

- (FBFutureContext<FBAFCConnection *> *)houseArrestAFCConnectionForBundleID:(NSString *)bundleID afcCalls:(AFCCalls)afcCalls
{
  return [[self
    connectToDeviceWithPurpose:@"house_arrest"]
    onQueue:self.workQueue replace:^ FBFutureContext<FBAFCConnection *> * (FBAMDevice *device) {
      return [[self.serviceManager
        houseArrestAFCConnectionForBundleID:bundleID afcCalls:afcCalls]
        utilizeWithPurpose:self.udid];
    }];
}

#pragma mark FBFutureContextManager Implementation

- (FBFuture<FBAMDevice *> *)prepare:(id<FBControlCoreLogger>)logger
{
  AMDeviceRef amDevice = self.amDevice;
  if (amDevice == NULL) {
    return [[FBDeviceControlError
      describe:@"Cannot utilize a non existent AMDeviceRef"]
      failFuture];
  }

  [logger log:@"Connecting to AMDevice"];
  int status = self.calls.Connect(amDevice);
  if (status != 0) {
    NSString *errorDescription = CFBridgingRelease(self.calls.CopyErrorText(status));
    return [[FBDeviceControlError
      describeFormat:@"Failed to connect to device. (%@)", errorDescription]
      failFuture];
  }

  [logger log:@"Starting Session on AMDevice"];
  status = self.calls.StartSession(amDevice);
  if (status != 0) {
    self.calls.Disconnect(amDevice);
    NSString *errorDescription = CFBridgingRelease(self.calls.CopyErrorText(status));
    return [[FBDeviceControlError
      describeFormat:@"Failed to start session with device. (%@)", errorDescription]
      failFuture];
  }

  [logger log:@"Device ready for use"];
  return [FBFuture futureWithResult:self];
}

- (FBFuture<NSNull *> *)teardown:(FBAMDevice *)device logger:(id<FBControlCoreLogger>)logger;
{
  AMDeviceRef amDevice = device.amDevice;
  [logger log:@"Stopping Session on AMDevice"];
  self.calls.StopSession(amDevice);

  [logger log:@"Disconnecting from AMDevice"];
  self.calls.Disconnect(amDevice);

  [logger log:@"Disconnected from AMDevice"];

  return FBFuture.empty;
}

- (NSString *)contextName
{
  return [NSString stringWithFormat:@"%@_connection", self.udid];
}

- (BOOL)isContextSharable
{
  return YES;
}

#pragma mark Private

static NSString *const CacheValuesPurpose = @"cache_values";

- (BOOL)cacheAllValues
{
  NSError *error = nil;
  FBAMDevice *device = [self.connectionContextManager utilizeNowWithPurpose:CacheValuesPurpose error:&error];
  [self.logger logFormat:@"Caching values for AMDeviceRef %@", device.amDevice];
  if (!device) {
    return NO;
  }
  // Contains all values, everything is derived
  _allValues = [CFBridgingRelease(self.calls.CopyValue(device.amDevice, NULL, NULL)) copy];

  [self.logger logFormat:@"Finished caching values for AMDeviceRef %@", device.amDevice];

  if (![self.connectionContextManager returnNowWithPurpose:CacheValuesPurpose error:nil]) {
    return NO;
  }
  return YES;
}

#pragma mark NSObject

- (id)device:(AMDeviceRef)device valueForKey:(NSString *)key
{
  return CFBridgingRelease(self.calls.CopyValue(device, NULL, (__bridge CFStringRef)(key)));
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"AMDevice %@ | %@",
    self.udid,
    self.name
  ];
}

#pragma mark Private

+ (NSString *)osVersionForDeviceClass:(NSString *)deviceClass productVersion:(NSString *)productVersion
{
  NSDictionary<NSString *, NSString *> *deviceClassOSPrefixMapping = @{
    @"iPhone" : @"iOS",
    @"iPad" : @"iOS",
  };
  NSString *osPrefix = deviceClassOSPrefixMapping[deviceClass];
  if (!osPrefix) {
    return productVersion;
  }
  return [NSString stringWithFormat:@"%@ %@", osPrefix, productVersion];
}

@end

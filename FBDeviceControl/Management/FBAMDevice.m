/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAMDevice.h"
#import "FBAMDevice+Private.h"

#import <FBControlCore/FBControlCore.h>

#include <dlfcn.h>

#import "FBDeviceControlError.h"

#pragma mark - Notifications

NSNotificationName const FBAMDeviceNotificationNameDeviceAttached = @"FBAMDeviceNotificationNameDeviceAttached";

NSNotificationName const FBAMDeviceNotificationNameDeviceDetached = @"FBAMDeviceNotificationNameDeviceDetached";

#pragma mark - AMDevice API

typedef struct afc_connection {
  unsigned int handle;            /* 0 */
  unsigned int unknown0;          /* 4 */
  unsigned char unknown1;         /* 8 */
  unsigned char padding[3];       /* 9 */
  unsigned int unknown2;          /* 12 */
  unsigned int unknown3;          /* 16 */
  unsigned int unknown4;          /* 20 */
  unsigned int fs_block_size;     /* 24 */
  unsigned int sock_block_size;   /* 28: always 0x3c */
  unsigned int io_timeout;        /* 32: from AFCConnectionOpen, usu. 0 */
  void *afc_lock;                 /* 36 */
  unsigned int context;           /* 40 */
} __attribute__ ((packed)) afc_connection;

typedef NS_ENUM(int, AMDeviceNotificationType) {
  AMDeviceNotificationTypeConnected = 1,
  AMDeviceNotificationTypeDisconnected = 2,
};

typedef struct {
  AMDeviceRef amDevice;
  AMDeviceNotificationType status;
} AMDeviceNotification;

// Managing Connections & Sessions.
int (*FB_AMDeviceConnect)(AMDeviceRef device);
int (*FB_AMDeviceDisconnect)(AMDeviceRef device);
int (*FB_AMDeviceIsPaired)(AMDeviceRef device);
int (*FB_AMDeviceValidatePairing)(AMDeviceRef device);
int (*FB_AMDeviceStartSession)(AMDeviceRef device);
int (*FB_AMDeviceStopSession)(AMDeviceRef device);

// Getting Properties of a Device.
_Nullable CFStringRef (*_Nonnull FB_AMDeviceCopyDeviceIdentifier)(AMDeviceRef device);
_Nullable CFStringRef (*_Nonnull FB_AMDeviceCopyValue)(AMDeviceRef device, _Nullable CFStringRef domain, CFStringRef name);

// Obtaining Devices.
_Nullable CFArrayRef (*_Nonnull FB_AMDCreateDeviceList)(void);
int (*FB_AMDeviceNotificationSubscribe)(void *callback, int arg0, int arg1, void *context, void **subscriptionOut);
int (*FB_AMDeviceNotificationUnsubscribe)(void *subscription);

// Using Connections.
int (*FB_AMDServiceConnectionGetSocket)(CFTypeRef connection);
int (*FB_AMDServiceConnectionInvalidate)(CFTypeRef connection);
int (*FB_AMDeviceSecureStartService)(AMDeviceRef device, CFStringRef service_name, _Nullable CFDictionaryRef userinfo, void *handle);
int (*FB_AMDeviceStartService)(AMDeviceRef device, CFStringRef service_name, void *handle, uint32_t *unknown);
int (*FB_AMDeviceSecureTransferPath)(int arg0, AMDeviceRef device, CFURLRef arg2, CFDictionaryRef arg3, void *_Nullable callback, void *_Nullable context);
int (*FB_AMDeviceSecureInstallApplication)(int arg0, AMDeviceRef device, CFURLRef arg2, CFDictionaryRef arg3, void *_Nullable callback, void *_Nullable context);
int (*FB_AMDeviceSecureUninstallApplication)(int arg0, AMDeviceRef device, CFStringRef arg2, int arg3, void *_Nullable callback, void *_Nullable context);
int (*FB_AMDeviceLookupApplications)(AMDeviceRef device, CFDictionaryRef _Nullable options, CFDictionaryRef _Nonnull * _Nonnull attributesOut);

// Debugging
void (*FB_AMDSetLogLevel)(int32_t level);
_Nullable CFStringRef (*FB_AMDCopyErrorText)(int status);

#pragma mark - FBAMDeviceListener

@interface FBAMDeviceManager : NSObject

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, FBAMDevice *> *devices;
@property (nonatomic, assign, readwrite) void *subscription;

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
      [manager.logger logFormat:@"Got Unknown status %d from FB_AMDeviceListenerCallback", notificationType];
      break;
  }
}

@implementation FBAMDeviceManager

+ (instancetype)sharedManager
{
  static dispatch_once_t onceToken;
  static FBAMDeviceManager *manager;
  dispatch_once(&onceToken, ^{
    manager = [self managerWithQueue:dispatch_get_main_queue() logger:FBControlCoreGlobalConfiguration.defaultLogger];
  });
  return manager;
}

+ (instancetype)managerWithQueue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  FBAMDeviceManager *manager = [[self alloc] initWithQueue:queue logger:logger];
  [manager populateFromList];
  NSError *error = nil;
  BOOL success = [manager startListeningWithError:&error];
  NSAssert(success, @"Failed to Start Listening %@", error);
  return manager;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _queue = queue;
  _logger = logger;
  _devices = [NSMutableDictionary dictionary];

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
  void *subscription = nil;
  int result = FB_AMDeviceNotificationSubscribe(
    FB_AMDeviceListenerCallback,
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

  int result = FB_AMDeviceNotificationUnsubscribe(self.subscription);
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

- (void)populateFromList
{
  CFArrayRef array = FB_AMDCreateDeviceList();
  for (NSInteger index = 0; index < CFArrayGetCount(array); index++) {
    AMDeviceRef value = CFArrayGetValueAtIndex(array, index);
    [self deviceConnected:value];
  }
  CFRelease(array);
}

- (void)deviceConnected:(AMDeviceRef)amDevice
{
  NSString *udid = CFBridgingRelease(FB_AMDeviceCopyDeviceIdentifier(amDevice));
  FBAMDevice *device = self.devices[udid];
  if (!device) {
    device = [[FBAMDevice alloc] initWithUDID:udid workQueue:self.queue];
    self.devices[udid] = device;
    [NSNotificationCenter.defaultCenter postNotificationName:FBAMDeviceNotificationNameDeviceAttached object:device];
  }
  if (amDevice != device.amDevice) {
    device.amDevice = amDevice;
  }
}

- (void)deviceDisconnected:(AMDeviceRef)amDevice
{
  NSString *udid = CFBridgingRelease(FB_AMDeviceCopyDeviceIdentifier(amDevice));
  FBAMDevice *device = self.devices[udid];
  if (!device) {
    return;
  }
  [self.devices removeObjectForKey:udid];
  [NSNotificationCenter.defaultCenter postNotificationName:FBAMDeviceNotificationNameDeviceDetached object:device];
}

- (NSArray<FBAMDevice *> *)currentDeviceList
{
  return [self.devices.allValues sortedArrayUsingSelector:@selector(udid)];
}

@end

#pragma mark - FBAMDevice Implementation

@implementation FBAMDevice

@synthesize amDevice = _amDevice;

#pragma mark Initializers

+ (void)setDefaultLogLevel:(int)level logFilePath:(NSString *)logFilePath
{
  NSNumber *levelNumber = @(level);
  CFPreferencesSetAppValue(CFSTR("LogLevel"), (__bridge CFPropertyListRef _Nullable)(levelNumber), CFSTR("com.apple.MobileDevice"));
  CFPreferencesSetAppValue(CFSTR("LogFile"), (__bridge CFPropertyListRef _Nullable)(logFilePath), CFSTR("com.apple.MobileDevice"));
}

+ (void)loadMobileDeviceSymbols
{
  NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.apple.mobiledevice"];
  NSCAssert(bundle.loaded, @"MobileDevice is not loaded");
  NSString *path = [bundle.bundlePath stringByAppendingPathComponent:@"Versions/Current/MobileDevice"];
  void *handle = dlopen(path.UTF8String, RTLD_LAZY);
  NSCAssert(handle, @"MobileDevice dlopen handle from %@ could not be obtained", path);
  FB_AMDCopyErrorText = FBGetSymbolFromHandle(handle, "AMDCopyErrorText");
  FB_AMDCreateDeviceList = FBGetSymbolFromHandle(handle, "AMDCreateDeviceList");
  FB_AMDeviceConnect = FBGetSymbolFromHandle(handle, "AMDeviceConnect");
  FB_AMDeviceCopyDeviceIdentifier = FBGetSymbolFromHandle(handle, "AMDeviceCopyDeviceIdentifier");
  FB_AMDeviceCopyValue = FBGetSymbolFromHandle(handle, "AMDeviceCopyValue");
  FB_AMDeviceDisconnect = FBGetSymbolFromHandle(handle, "AMDeviceDisconnect");
  FB_AMDeviceIsPaired = FBGetSymbolFromHandle(handle, "AMDeviceIsPaired");
  FB_AMDeviceLookupApplications = FBGetSymbolFromHandle(handle, "AMDeviceLookupApplications");
  FB_AMDeviceNotificationSubscribe = FBGetSymbolFromHandle(handle, "AMDeviceNotificationSubscribe");
  FB_AMDeviceNotificationUnsubscribe = FBGetSymbolFromHandle(handle, "AMDeviceNotificationUnsubscribe");
  FB_AMDeviceSecureInstallApplication = FBGetSymbolFromHandle(handle, "AMDeviceSecureInstallApplication");
  FB_AMDeviceSecureStartService = FBGetSymbolFromHandle(handle, "AMDeviceSecureStartService");
  FB_AMDeviceSecureTransferPath = FBGetSymbolFromHandle(handle, "AMDeviceSecureTransferPath");
  FB_AMDeviceSecureUninstallApplication = FBGetSymbolFromHandle(handle, "AMDeviceSecureUninstallApplication");
  FB_AMDeviceStartService = FBGetSymbolFromHandle(handle, "AMDeviceStartService");
  FB_AMDeviceStartSession = FBGetSymbolFromHandle(handle, "AMDeviceStartSession");
  FB_AMDeviceStopSession = FBGetSymbolFromHandle(handle, "AMDeviceStopSession");
  FB_AMDeviceValidatePairing = FBGetSymbolFromHandle(handle, "AMDeviceValidatePairing");
  FB_AMDServiceConnectionGetSocket = FBGetSymbolFromHandle(handle, "AMDServiceConnectionGetSocket");
  FB_AMDServiceConnectionInvalidate = FBGetSymbolFromHandle(handle, "AMDServiceConnectionInvalidate");
  FB_AMDSetLogLevel = FBGetSymbolFromHandle(handle, "AMDSetLogLevel");
}

+ (NSArray<FBAMDevice *> *)allDevices
{
  return FBAMDeviceManager.sharedManager.currentDeviceList;
}

- (instancetype)initWithUDID:(NSString *)udid workQueue:(dispatch_queue_t)workQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _udid = udid;
  _workQueue = workQueue;

  return self;
}

#pragma mark Properties

- (void)setAmDevice:(AMDeviceRef)amDevice
{
  AMDeviceRef oldAMDevice = _amDevice;
  _amDevice = amDevice;
  if (amDevice) {
    CFRetain(amDevice);
    [self cacheAllValues];
  }
  if (oldAMDevice) {
    CFRelease(oldAMDevice);
  }
}

- (AMDeviceRef)amDevice
{
  return _amDevice;
}

#pragma mark Public Methods

- (FBFuture *)futureForDeviceOperation:(id(^)(AMDeviceRef, NSError **))block
{
  return [FBFuture onQueue:self.workQueue resolveValue:^(NSError **error) {
    return [self performOnConnectedDevice:block error:error];
  }];
}

- (FBFuture<NSValue *> *)startService:(NSString *)service userInfo:(NSDictionary *)userInfo
{
  return [self futureForDeviceOperation:^ NSValue * (AMDeviceRef device, NSError **error) {
    afc_connection afcConnection;
    int status = FB_AMDeviceSecureStartService(
      device,
      (__bridge CFStringRef)(service),
      (__bridge CFDictionaryRef)(userInfo),
      &afcConnection
    );
    if (status != 0) {
      NSString *errorDescription = CFBridgingRelease(FB_AMDCopyErrorText(status));
      return [[FBDeviceControlError
        describeFormat:@"Start Service Failed with %d %@", status, errorDescription]
        fail:error];
    }
    return [NSValue valueWithPointer:&afcConnection];
  }];
}

- (FBFuture<NSValue *> *)startTestManagerService
{
  NSDictionary *userInfo = @{
    @"CloseOnInvalidate" : @1,
    @"InvalidateOnDetach" : @1
  };
  return [self startService:@"com.apple.testmanagerd.lockdown" userInfo:userInfo];
}

- (void)dealloc
{
  CFRelease(_amDevice);
}

#pragma mark Private

- (BOOL)cacheAllValues
{
  return [self performOnConnectedDevice:^(AMDeviceRef device, NSError **erro) {
    self->_deviceName = CFBridgingRelease(FB_AMDeviceCopyValue(device, NULL, CFSTR("DeviceName")));
    self->_modelName = CFBridgingRelease(FB_AMDeviceCopyValue(device, NULL, CFSTR("DeviceClass")));
    self->_systemVersion = CFBridgingRelease(FB_AMDeviceCopyValue(device, NULL, CFSTR("ProductVersion")));
    self->_productType = CFBridgingRelease(FB_AMDeviceCopyValue(device, NULL, CFSTR("ProductType")));
    self->_architecture = CFBridgingRelease(FB_AMDeviceCopyValue(device, NULL, CFSTR("CPUArchitecture")));

    NSString *osVersion = [FBAMDevice osVersionForDevice:device];
    self->_deviceConfiguration = FBControlCoreConfigurationVariants.productTypeToDevice[self->_productType];
    self->_osConfiguration = FBControlCoreConfigurationVariants.nameToOSVersion[osVersion] ?: [FBOSVersion genericWithName:osVersion];
    return @YES;
  } error:nil] != nil;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"AMDevice %@ | %@",
    self.udid,
    self.deviceName
  ];
}

#pragma mark Private

+ (NSString *)osVersionForDevice:(AMDeviceRef)amDevice
{
  NSString *deviceClass = CFBridgingRelease(FB_AMDeviceCopyValue(amDevice, NULL, CFSTR("DeviceClass")));
  NSString *productVersion = CFBridgingRelease(FB_AMDeviceCopyValue(amDevice, NULL, CFSTR("ProductVersion")));
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

- (id)performOnConnectedDevice:(id(^)(AMDeviceRef, NSError **))block error:(NSError **)error
{
  AMDeviceRef amDevice = self.amDevice;
  int status = FB_AMDeviceConnect(amDevice);
  if (status != 0) {
    NSString *errorDecription = CFBridgingRelease(FB_AMDCopyErrorText(status));
    return [[FBDeviceControlError
      describeFormat:@"Failed to connect to device. (%@)", errorDecription]
      failFuture];
  }
  status = FB_AMDeviceStartSession(amDevice);
  if (status != 0) {
    FB_AMDeviceDisconnect(amDevice);
    NSString *errorDecription = CFBridgingRelease(FB_AMDCopyErrorText(status));
    return [[FBDeviceControlError
      describeFormat:@"Failed to start session with device. (%@)", errorDecription]
      failFuture];
  }
  id result = block(amDevice, error);
  FB_AMDeviceStopSession(amDevice);
  return result;
}

@end

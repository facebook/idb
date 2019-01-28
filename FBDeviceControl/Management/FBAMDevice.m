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

#import "FBAMDServiceConnection.h"
#import "FBDeviceControlError.h"
#import "FBAFCConnection.h"
#import "FBAMDeviceServiceManager.h"

#pragma mark - Notifications

NSNotificationName const FBAMDeviceNotificationNameDeviceAttached = @"FBAMDeviceNotificationNameDeviceAttached";

NSNotificationName const FBAMDeviceNotificationNameDeviceDetached = @"FBAMDeviceNotificationNameDeviceDetached";

#pragma mark - FBAMDeviceListener

@interface FBAMDeviceManager : NSObject

@property (nonatomic, assign, readonly) AMDCalls calls;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, FBAMDevice *> *devices;
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
    manager = [self managerWithCalls:FBAMDevice.defaultCalls Queue:dispatch_get_main_queue() logger:logger];
  });
  return manager;
}

+ (instancetype)managerWithCalls:(AMDCalls)calls Queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  FBAMDeviceManager *manager = [[self alloc] initWithCalls:calls queue:queue logger:logger];
  [manager populateFromList];
  NSError *error = nil;
  BOOL success = [manager startListeningWithError:&error];
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

- (void)populateFromList
{
  CFArrayRef array = self.calls.CreateDeviceList();
  for (NSInteger index = 0; index < CFArrayGetCount(array); index++) {
    AMDeviceRef value = CFArrayGetValueAtIndex(array, index);
    [self deviceConnected:value];
  }
  CFRelease(array);
}

static const NSTimeInterval ConnectionReuseTimeout = 10.0;
static const NSTimeInterval ServiceReuseTimeout = 6.0;

- (void)deviceConnected:(AMDeviceRef)amDevice
{
  [self.logger logFormat:@"Device Connected %@", amDevice];
  NSString *udid = CFBridgingRelease(self.calls.CopyDeviceIdentifier(amDevice));
  FBAMDevice *device = self.devices[udid];
  if (!device) {
    device = [[FBAMDevice alloc] initWithUDID:udid calls:self.calls connectionReuseTimeout:@(ConnectionReuseTimeout) serviceReuseTimeout:@(ServiceReuseTimeout) workQueue:self.queue logger:self.logger];
    self.devices[udid] = device;
  }
  AMDeviceRef oldDevice = device.amDevice;
  if (oldDevice == NULL) {
    [self.logger logFormat:@"New Device '%@' appeared for the first time", amDevice];
    device.amDevice = amDevice;
  } else if (amDevice != oldDevice) {
    [self.logger logFormat:@"New Device '%@' replaces Old Device '%@'", amDevice, oldDevice];
    device.amDevice = amDevice;
  } else {
    [self.logger logFormat:@"Existing Device %@ is the same as the old", amDevice];
  }
  [NSNotificationCenter.defaultCenter postNotificationName:FBAMDeviceNotificationNameDeviceAttached object:device.udid];
}

- (void)deviceDisconnected:(AMDeviceRef)amDevice
{
  [self.logger logFormat:@"Device Disconnected %@", amDevice];
  NSString *udid = CFBridgingRelease(self.calls.CopyDeviceIdentifier(amDevice));
  FBAMDevice *device = self.devices[udid];
  if (!device) {
    [self.logger logFormat:@"No Device named %@ from inflated devices, nothing to remove", udid];
    return;
  } 
  [self.logger logFormat:@"Removing Device %@ from inflated devices", udid];
  [self.devices removeObjectForKey:udid];
  [NSNotificationCenter.defaultCenter postNotificationName:FBAMDeviceNotificationNameDeviceDetached object:device.udid];
}

- (NSArray<FBAMDevice *> *)currentDeviceList
{
  return [self.devices.allValues sortedArrayUsingSelector:@selector(udid)];
}

@end

#pragma mark - FBAMDevice Implementation

@implementation FBAMDevice

@synthesize amDevice = _amDevice;
@synthesize contextPoolTimeout = _contextPoolTimeout;

#pragma mark Initializers

+ (void)setDefaultLogLevel:(int)level logFilePath:(NSString *)logFilePath
{
  NSNumber *levelNumber = @(level);
  CFPreferencesSetAppValue(CFSTR("LogLevel"), (__bridge CFPropertyListRef _Nullable)(levelNumber), CFSTR("com.apple.MobileDevice"));
  CFPreferencesSetAppValue(CFSTR("LogFile"), (__bridge CFPropertyListRef _Nullable)(logFilePath), CFSTR("com.apple.MobileDevice"));
}

+ (AMDCalls)defaultCalls
{
  static dispatch_once_t onceToken;
  static AMDCalls defaultCalls;
  dispatch_once(&onceToken, ^{
    [self populateMobileDeviceSymbols:&defaultCalls];
  });
  return defaultCalls;
}

+ (void)populateMobileDeviceSymbols:(AMDCalls *)calls
{
  void *handle = [[NSBundle bundleWithIdentifier:@"com.apple.mobiledevice"] dlopenExecutablePath];
  calls->Connect = FBGetSymbolFromHandle(handle, "AMDeviceConnect");
  calls->CopyDeviceIdentifier = FBGetSymbolFromHandle(handle, "AMDeviceCopyDeviceIdentifier");
  calls->CopyErrorText = FBGetSymbolFromHandle(handle, "AMDCopyErrorText");
  calls->CopyValue = FBGetSymbolFromHandle(handle, "AMDeviceCopyValue");
  calls->CreateDeviceList = FBGetSymbolFromHandle(handle, "AMDCreateDeviceList");
  calls->CreateHouseArrestService = FBGetSymbolFromHandle(handle, "AMDeviceCreateHouseArrestService");
  calls->Disconnect = FBGetSymbolFromHandle(handle, "AMDeviceDisconnect");
  calls->IsPaired = FBGetSymbolFromHandle(handle, "AMDeviceIsPaired");
  calls->LookupApplications = FBGetSymbolFromHandle(handle, "AMDeviceLookupApplications");
  calls->MountImage = FBGetSymbolFromHandle(handle, "AMDeviceMountImage");
  calls->NotificationSubscribe = FBGetSymbolFromHandle(handle, "AMDeviceNotificationSubscribe");
  calls->NotificationUnsubscribe = FBGetSymbolFromHandle(handle, "AMDeviceNotificationUnsubscribe");
  calls->Release = FBGetSymbolFromHandle(handle, "AMDeviceRelease");
  calls->Retain = FBGetSymbolFromHandle(handle, "AMDeviceRetain");
  calls->SecureInstallApplication = FBGetSymbolFromHandle(handle, "AMDeviceSecureInstallApplication");
  calls->SecureStartService = FBGetSymbolFromHandle(handle, "AMDeviceSecureStartService");
  calls->SecureTransferPath = FBGetSymbolFromHandle(handle, "AMDeviceSecureTransferPath");
  calls->SecureUninstallApplication = FBGetSymbolFromHandle(handle, "AMDeviceSecureUninstallApplication");
  calls->ServiceConnectionGetSecureIOContext = FBGetSymbolFromHandle(handle, "AMDServiceConnectionGetSecureIOContext");
  calls->ServiceConnectionGetSocket = FBGetSymbolFromHandle(handle, "AMDServiceConnectionGetSocket");
  calls->ServiceConnectionInvalidate = FBGetSymbolFromHandle(handle, "AMDServiceConnectionInvalidate");
  calls->ServiceConnectionReceive = FBGetSymbolFromHandle(handle, "AMDServiceConnectionReceive");
  calls->ServiceConnectionSend = FBGetSymbolFromHandle(handle, "AMDServiceConnectionSend");
  calls->SetLogLevel = FBGetSymbolFromHandle(handle, "AMDSetLogLevel");
  calls->StartSession = FBGetSymbolFromHandle(handle, "AMDeviceStartSession");
  calls->StopSession = FBGetSymbolFromHandle(handle, "AMDeviceStopSession");
  calls->ValidatePairing = FBGetSymbolFromHandle(handle, "AMDeviceValidatePairing");
}

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
  return [[self
    connectToDeviceWithPurpose:@"start_service_%@", service]
    onQueue:self.workQueue push:^(FBAMDevice *device) {
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
          describeFormat:@"Start Service Failed with %d %@", status, errorDescription]
          logger:self.logger]
          failFutureContext];
      }
      FBAMDServiceConnection *connection = [[FBAMDServiceConnection alloc] initWithServiceConnection:serviceConnection device:device.amDevice calls:self.calls logger:self.logger];
      [self.logger logFormat:@"Service %@ started", service];
      return [[FBFuture
        futureWithResult:connection]
        onQueue:self.workQueue contextualTeardown:^(id _, FBFutureState __) {
          [self.logger logFormat:@"Invalidating service %@", service];
          NSError *error = nil;
          if (![connection invalidateWithError:&error]) {
            [self.logger logFormat:@"Failed to invalidate service %@ with error %@", service, error];
          } else {
            [self.logger logFormat:@"Invalidated service %@", service];
          }
        }];
    }];
}

- (FBFutureContext<FBAMDServiceConnection *> *)startAFCService
{
  return [self startService:@"com.apple.afc"];
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
    onQueue:self.workQueue push:^ FBFutureContext<FBAFCConnection *> * (FBAMDevice *device) {
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

  return [FBFuture futureWithResult:NSNull.null];
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
  _architecture = CFBridgingRelease(self.calls.CopyValue(device.amDevice, NULL, CFSTR("CPUArchitecture")));
  _buildVersion = CFBridgingRelease(self.calls.CopyValue(device.amDevice, NULL, CFSTR("BuildVersion")));
  _deviceName = CFBridgingRelease(self.calls.CopyValue(device.amDevice, NULL, CFSTR("DeviceName")));
  _modelName = CFBridgingRelease(self.calls.CopyValue(device.amDevice, NULL, CFSTR("DeviceClass")));
  _productType = CFBridgingRelease(self.calls.CopyValue(device.amDevice, NULL, CFSTR("ProductType")));
  _productVersion = CFBridgingRelease(self.calls.CopyValue(device.amDevice, NULL, CFSTR("ProductVersion")));

  NSString *osVersion = [FBAMDevice osVersionForDevice:device.amDevice calls:self.calls];
  _deviceConfiguration = FBiOSTargetConfiguration.productTypeToDevice[self->_productType];
  _osConfiguration = FBiOSTargetConfiguration.nameToOSVersion[osVersion] ?: [FBOSVersion genericWithName:osVersion];

  [self.logger logFormat:@"Finished caching values for AMDeviceRef %@", device.amDevice];

  if (![self.connectionContextManager returnNowWithPurpose:CacheValuesPurpose error:nil]) {
    return NO;
  }
  return YES;
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

+ (NSString *)osVersionForDevice:(AMDeviceRef)amDevice calls:(AMDCalls)calls
{
  NSString *deviceClass = CFBridgingRelease(calls.CopyValue(amDevice, NULL, CFSTR("DeviceClass")));
  NSString *productVersion = CFBridgingRelease(calls.CopyValue(amDevice, NULL, CFSTR("ProductVersion")));
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

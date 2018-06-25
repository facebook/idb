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

#pragma mark - Notifications

NSNotificationName const FBAMDeviceNotificationNameDeviceAttached = @"FBAMDeviceNotificationNameDeviceAttached";

NSNotificationName const FBAMDeviceNotificationNameDeviceDetached = @"FBAMDeviceNotificationNameDeviceDetached";

#pragma mark - AMDevice API

typedef NS_ENUM(int, AMDeviceNotificationType) {
  AMDeviceNotificationTypeConnected = 1,
  AMDeviceNotificationTypeDisconnected = 2,
};

typedef struct {
  AMDeviceRef amDevice;
  AMDeviceNotificationType status;
} AMDeviceNotification;

#pragma mark - FBAMDeviceListener

@interface FBAMDeviceManager : NSObject

@property (nonatomic, assign, readonly) AMDCalls calls;
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
  void *subscription = nil;
  int result = self.calls.NotificationSubscribe(
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

- (void)deviceConnected:(AMDeviceRef)amDevice
{
  NSString *udid = CFBridgingRelease(self.calls.CopyDeviceIdentifier(amDevice));
  FBAMDevice *device = self.devices[udid];
  if (!device) {
    device = [[FBAMDevice alloc] initWithUDID:udid calls:self.calls workQueue:self.queue logger:self.logger];
    self.devices[udid] = device;
    [NSNotificationCenter.defaultCenter postNotificationName:FBAMDeviceNotificationNameDeviceAttached object:device];
  }
  if (amDevice != device.amDevice) {
    device.amDevice = amDevice;
  }
}

- (void)deviceDisconnected:(AMDeviceRef)amDevice
{
  NSString *udid = CFBridgingRelease(self.calls.CopyDeviceIdentifier(amDevice));
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

#pragma mark - FBAMDeviceConnection

@interface FBAMDeviceConnection ()

@property (nonatomic, copy, readonly) NSString *udid;
@property (nonatomic, assign, readonly) AMDCalls calls;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) NSMutableArray<FBMutableFuture<NSNull *> *> *pending;
@property (nonatomic, strong, nullable, readwrite) FBFuture<NSNull *> *current;
@property (nonatomic, assign, readwrite) BOOL connected;

@end

@implementation FBAMDeviceConnection

- (instancetype)initWithUDID:(NSString *)udid device:(AMDeviceRef)device calls:(AMDCalls)calls queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _udid = udid;
  _device = device;
  _calls = calls;
  _logger = logger;
  _queue = queue;
  _pending = [NSMutableArray array];
  _connected = NO;

  return self;
}

- (id<FBControlCoreLogger>)loggerWithPurpose:(NSString *)purpose
{
  return [self.logger withName:[NSString stringWithFormat:@"%@_%@", self.udid, purpose]];
}

- (FBFutureContext<FBAMDeviceConnection *> *)utilizeWithPurpose:(NSString *)purpose
{
  id<FBControlCoreLogger> logger = [self loggerWithPurpose:purpose];
  return [[[self
    deviceNoLongerInUseWithLogger:logger]
    onQueue:self.queue fmap:^(id _){
      if (self.connected) {
        [logger log:@"Re-Using existing connection"];
        return [FBFuture futureWithResult:self];
      }
      NSError *error = nil;
      [logger log:@"No active connection, connecting"];
      if (![self connectToDeviceNow:purpose error:&error]) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:self];
    }]
    onQueue:self.queue contextualTeardown:^(id _) {
      NSUInteger remainingConsumers = [self popQueue];
      if (remainingConsumers == 0) {
        [logger log:@"No more consumers, disconnecting"];
        [self disconnectFromDeviceNow:purpose error:nil];
      } else {
        [logger logFormat:@"%lu More consumers waiting, not disconnecting", remainingConsumers];
      }
    }];
}

- (FBFuture<NSNull *> *)deviceNoLongerInUseWithLogger:(id<FBControlCoreLogger>)logger
{
  return [FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSNull *> * {
      if (self.current) {
        [logger logFormat:@"Device currently in use, waiting"];
        FBMutableFuture<NSNull *> *deviceAvailable = FBMutableFuture.future;
        [self.pending addObject:deviceAvailable];
        return deviceAvailable;
      }
      [logger logFormat:@"Device immediately available"];
      self.current = [FBFuture futureWithResult:NSNull.null];
      return self.current;
    }];
}

- (AMDeviceRef)connectToDeviceNow:(NSString *)purpose error:(NSError **)error
{
  id<FBControlCoreLogger> logger = [self loggerWithPurpose:purpose];
  AMDeviceRef amDevice = self.device;
  if (amDevice == NULL) {
    return [[FBDeviceControlError
      describe:@"Cannot utilize a non existent AMDeviceRef"]
      failPointer:error];
  }
  if (self.connected) {
    return [[FBDeviceControlError
      describe:@"Cannot utilize device when it is already in use"]
      failPointer:error];
  }

  [logger log:@"Connecting to AMDevice"];
  int status = self.calls.Connect(amDevice);
  if (status != 0) {
    NSString *errorDecription = CFBridgingRelease(self.calls.CopyErrorText(status));
    return [[FBDeviceControlError
      describeFormat:@"Failed to connect to device. (%@)", errorDecription]
      failPointer:error];
  }

  [logger log:@"Starting Session on AMDevice"];
  status = self.calls.StartSession(amDevice);
  if (status != 0) {
    self.calls.Disconnect(amDevice);
    NSString *errorDecription = CFBridgingRelease(self.calls.CopyErrorText(status));
    return [[FBDeviceControlError
      describeFormat:@"Failed to start session with device. (%@)", errorDecription]
      failPointer:error];
  }

  [logger log:@"Device ready for use"];
  self.connected = YES;
  return amDevice;
}

- (BOOL)disconnectFromDeviceNow:(NSString *)purpose error:(NSError **)error
{
  id<FBControlCoreLogger> logger = [self loggerWithPurpose:purpose];
  if (!self.connected) {
    return [[FBDeviceControlError
      describe:@"Cannot utilize device when it is not in use"]
      failBool:error];
  }

  AMDeviceRef amDevice = self.device;
  [logger log:@"Stopping Session on AMDevice"];
  self.calls.StopSession(amDevice);

  [logger log:@"Disconnecting from AMDevice"];
  self.calls.Disconnect(amDevice);

  [logger log:@"Disconnected from AMDevice"];
  self.connected = NO;

  return YES;
}

- (NSUInteger)popQueue
{
  NSUInteger pendingConsumers = self.pending.count;
  if (pendingConsumers == 0) {
    self.current = nil;
    return 0;
  }
  FBMutableFuture<NSNull *> *future = [self.pending lastObject];
  [self.pending removeLastObject];
  [future resolveWithResult:NSNull.null];
  self.current = future;
  return pendingConsumers;
}

- (void)deviceReferenceChanged:(AMDeviceRef)device
{
  AMDeviceRef oldAMDevice = _device;
  _device = device;
  if (device) {
    self.calls.Retain(device);
  }
  if (oldAMDevice) {
    self.calls.Release(oldAMDevice);
  }
}

- (void)dealloc
{
  if (_device) {
    self.calls.Release(_device);
    _device = NULL;
  }
}

@end

#pragma mark - FBAMDevice Implementation

@implementation FBAMDevice

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
  calls->SetLogLevel = FBGetSymbolFromHandle(handle, "AMDSetLogLevel");
  calls->StartSession = FBGetSymbolFromHandle(handle, "AMDeviceStartSession");
  calls->StopSession = FBGetSymbolFromHandle(handle, "AMDeviceStopSession");
  calls->ValidatePairing = FBGetSymbolFromHandle(handle, "AMDeviceValidatePairing");
}

+ (NSArray<FBAMDevice *> *)allDevices
{
  return FBAMDeviceManager.sharedManager.currentDeviceList;
}

- (instancetype)initWithUDID:(NSString *)udid calls:(AMDCalls)calls workQueue:(dispatch_queue_t)workQueue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _udid = udid;
  _calls = calls;
  _workQueue = workQueue;
  _logger = [logger withName:udid];
  _connection = [[FBAMDeviceConnection alloc] initWithUDID:udid device:NULL calls:calls queue:workQueue logger:logger];

  return self;
}

#pragma mark Properties

- (void)setAmDevice:(AMDeviceRef)amDevice
{
  [self.connection deviceReferenceChanged:amDevice];
  [self cacheAllValues];
}

- (AMDeviceRef)amDevice
{
  return self.connection.device;
}

#pragma mark Public Methods

- (FBFutureContext<FBAMDeviceConnection *> *)connectToDeviceWithPurpose:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  return [self.connection utilizeWithPurpose:string];
}

- (FBFutureContext<FBAMDServiceConnection *> *)startService:(NSString *)service userInfo:(NSDictionary *)userInfo
{
  return [[self
    connectToDeviceWithPurpose:@"start_service_%@", service]
    onQueue:self.workQueue push:^(FBAMDeviceConnection *connectedDevice) {
      AMDServiceConnectionRef serviceConnection;
      [self.logger logFormat:@"Starting service %@", service];
      int status = self.calls.SecureStartService(
        connectedDevice.device,
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
      FBAMDServiceConnection *connection = [[FBAMDServiceConnection alloc] initWithServiceConnection:serviceConnection device:connectedDevice.device calls:self.calls logger:self.logger];
      [self.logger logFormat:@"Service %@ started", service];
      return [[FBFuture
        futureWithResult:connection]
        onQueue:self.workQueue contextualTeardown:^(id _) {
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
  return [self startService:@"com.apple.afc" userInfo:@{}];
}

- (FBFutureContext<FBAMDServiceConnection *> *)startTestManagerService
{
  NSDictionary *userInfo = @{
    @"CloseOnInvalidate" : @1,
    @"InvalidateOnDetach" : @1
  };
  return [self startService:@"com.apple.testmanagerd.lockdown" userInfo:userInfo];
}

- (FBFutureContext<FBAFCConnection *> *)houseArrestAFCConnectionForBundleID:(NSString *)bundleID afcCalls:(AFCCalls)afcCalls
{
  return [[self
    connectToDeviceWithPurpose:@"house_arrest_%@", bundleID]
    onQueue:self.workQueue push:^ FBFutureContext<FBAFCConnection *> * (FBAMDeviceConnection *connectedDevice) {
      AFCConnectionRef afcConnection = NULL;
      [self.logger logFormat:@"Starting house arrest for '%@'", bundleID];
      int status = self.calls.CreateHouseArrestService(
        connectedDevice.device,
        (__bridge CFStringRef _Nonnull)(bundleID),
        NULL,
        &afcConnection
      );
      if (status != 0) {
        NSString *internalMessage = CFBridgingRelease(self.calls.CopyErrorText(status));
        return [[[FBDeviceControlError
          describeFormat:@"Failed to start house_arrest service for '%@' with error (%@)", bundleID, internalMessage]
          logger:self.logger]
          failFutureContext];
      }
      FBAFCConnection *connection = [[FBAFCConnection alloc] initWithConnection:afcConnection calls:afcCalls logger:self.logger];
      return [[FBFuture
        futureWithResult:connection]
        onQueue:self.workQueue contextualTeardown:^(id _) {
          [self.logger logFormat:@"Closing connection to House Arrest for '%@'", bundleID];
          NSError *error = nil;
          if (![connection closeWithError:&error]) {
            [self.logger logFormat:@"Failed to close House Arrest for '%@' with error %@", bundleID, error];
          } else {
            [self.logger logFormat:@"Closed House Arrest service for '%@'", bundleID];
          }
        }];
  }];
}

#pragma mark Private

static NSString *const CacheValuesPurpose = @"cache_values";

- (BOOL)cacheAllValues
{
  FBAMDeviceConnection *connection = self.connection;
  NSError *error = nil;
  AMDeviceRef device = [connection connectToDeviceNow:CacheValuesPurpose error:&error];
  if (!device) {
    return NO;
  }
  _deviceName = CFBridgingRelease(self.calls.CopyValue(device, NULL, CFSTR("DeviceName")));
  _modelName = CFBridgingRelease(self.calls.CopyValue(device, NULL, CFSTR("DeviceClass")));
  _systemVersion = CFBridgingRelease(self.calls.CopyValue(device, NULL, CFSTR("ProductVersion")));
  _productType = CFBridgingRelease(self.calls.CopyValue(device, NULL, CFSTR("ProductType")));
  _architecture = CFBridgingRelease(self.calls.CopyValue(device, NULL, CFSTR("CPUArchitecture")));

  NSString *osVersion = [FBAMDevice osVersionForDevice:device calls:self.calls];
  _deviceConfiguration = FBiOSTargetConfiguration.productTypeToDevice[self->_productType];
  _osConfiguration = FBiOSTargetConfiguration.nameToOSVersion[osVersion] ?: [FBOSVersion genericWithName:osVersion];

  if (![connection disconnectFromDeviceNow:CacheValuesPurpose error:nil]) {
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

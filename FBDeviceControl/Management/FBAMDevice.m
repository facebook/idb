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
    manager = [self managerWithCalls:FBAMDevice.defaultCalls Queue:dispatch_get_main_queue() logger:FBControlCoreGlobalConfiguration.defaultLogger];
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

@interface FBAMDeviceConnection ()

@property (nonatomic, assign, readonly) AMDCalls calls;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, assign, readwrite) NSUInteger utilizationCount;

@end

@implementation FBAMDeviceConnection

- (instancetype)initWithDevice:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];

  if (!self) {
    return nil;
  }

  _device = device;
  _calls = calls;
  _logger = logger;
  _utilizationCount = 0;

  return self;
}

- (AMDeviceRef)useDeviceWithError:(NSError **)error
{
  AMDeviceRef amDevice = self.device;
  if (amDevice == NULL) {
    return [[FBDeviceControlError
      describe:@"Cannot utilize a non existent AMDeviceRef"]
      failPointer:error];
  }
  if (self.utilizationCount != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Cannot utilize device when it has a utilization count of %lu", self.utilizationCount]
      failPointer:error];
  }

  [self.logger log:@"Connecting to AMDevice"];
  int status = self.calls.Connect(amDevice);
  if (status != 0) {
    NSString *errorDecription = CFBridgingRelease(self.calls.CopyErrorText(status));
    return [[FBDeviceControlError
      describeFormat:@"Failed to connect to device. (%@)", errorDecription]
      failPointer:error];
  }
  [self.logger log:@"Starting Session on AMDevice"];
  status = self.calls.StartSession(amDevice);
  if (status != 0) {
    self.calls.Disconnect(amDevice);
    NSString *errorDecription = CFBridgingRelease(self.calls.CopyErrorText(status));
    return [[FBDeviceControlError
      describeFormat:@"Failed to start session with device. (%@)", errorDecription]
      failPointer:error];
  }
  [self.logger log:@"Device ready for use"];
  self.utilizationCount++;
  return amDevice;
}

- (BOOL)endUsageWithError:(NSError **)error
{
  if (self.utilizationCount != 1) {
    return [[FBDeviceControlError
      describeFormat:@"Cannot utilize device when it has a utilization count of %lu", self.utilizationCount]
      failBool:error];
  }
  AMDeviceRef amDevice = self.device;
  [self.logger log:@"Stopping Session on AMDevice"];
  self.calls.StopSession(amDevice);
  [self.logger log:@"Disconnecting from AMDevice"];
  self.calls.Disconnect(amDevice);
  [self.logger log:@"Disconnected from AMDevice"];
  self.utilizationCount--;
  return YES;
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

  return self;
}

#pragma mark Properties

- (void)setAmDevice:(AMDeviceRef)amDevice
{
  AMDeviceRef oldAMDevice = _amDevice;
  _amDevice = amDevice;
  if (amDevice) {
    self.calls.Retain(amDevice);
    [self cacheAllValues];
  }
  if (oldAMDevice) {
    self.calls.Release(oldAMDevice);
  }
}

- (AMDeviceRef)amDevice
{
  return _amDevice;
}

#pragma mark Public Methods

- (FBFutureContext<FBAMDeviceConnection *> *)connectToDevice;
{
  return [[FBFuture
    onQueue:self.workQueue resolve:^{
      FBAMDeviceConnection *connection = self.connection;
      NSError *error = nil;
      AMDeviceRef device = [connection useDeviceWithError:&error];
      if (!device) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:connection];
    }]
    onQueue:self.workQueue contextualTeardown:^(FBAMDeviceConnection *connection) {
      [connection endUsageWithError:nil];
    }];
}

- (FBFutureContext<FBAMDServiceConnection *> *)startService:(NSString *)service userInfo:(NSDictionary *)userInfo
{
  return [[self
    connectToDevice]
    onQueue:self.workQueue pend:^(FBAMDeviceConnection *connectedDevice) {
      AMDServiceConnectionRef connection;
      int status = self.calls.SecureStartService(
        connectedDevice.device,
        (__bridge CFStringRef)(service),
        (__bridge CFDictionaryRef)(userInfo),
        &connection
      );
      if (status != 0) {
        NSString *errorDescription = CFBridgingRelease(self.calls.CopyErrorText(status));
        return [[FBDeviceControlError
          describeFormat:@"Start Service Failed with %d %@", status, errorDescription]
          failFuture];
      }
      return [FBFuture futureWithResult:[[FBAMDServiceConnection alloc] initWithServiceConnection:connection device:connectedDevice.device calls:self.calls]];
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
    connectToDevice]
    onQueue:self.workQueue push:^ FBFutureContext<FBAFCConnection *> * (FBAMDeviceConnection *connectedDevice) {
      AFCConnectionRef afcConnection = NULL;
      int status = self.calls.CreateHouseArrestService(
        connectedDevice.device,
        (__bridge CFStringRef _Nonnull)(bundleID),
        NULL,
        &afcConnection
      );
      if (status != 0) {
        NSString *internalMessage = CFBridgingRelease(self.calls.CopyErrorText(status));
        return [[FBDeviceControlError
          describeFormat:@"Failed to start house_arrest service (%@)", internalMessage]
          failFutureContext];
      }
      FBAFCConnection *connection = [[FBAFCConnection alloc] initWithConnection:afcConnection calls:afcCalls];
      return [[FBFuture
        futureWithResult:connection]
        onQueue:self.workQueue contextualTeardown:^(id _) {
        connection.calls.ConnectionClose(afcConnection);
    }];
  }];
}


- (void)dealloc
{
  if (_amDevice) {
    self.calls.Release(_amDevice);
    _amDevice = NULL;   
  }
}

#pragma mark Private

- (BOOL)cacheAllValues
{
  FBAMDeviceConnection *connection = self.connection;
  AMDeviceRef device = [connection useDeviceWithError:nil];
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

  if (![connection endUsageWithError:nil]) {
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

- (FBAMDeviceConnection *)connection
{
  return [[FBAMDeviceConnection alloc] initWithDevice:self.amDevice calls:self.calls logger:FBControlCoreGlobalConfiguration.defaultLogger];
}

@end

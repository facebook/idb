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

// Getting a full Device List
_Nullable CFArrayRef (*_Nonnull FB_AMDCreateDeviceList)(void);

// Using Connections.
int (*FB_AMDServiceConnectionGetSocket)(CFTypeRef connection);
int (*FB_AMDServiceConnectionInvalidate)(CFTypeRef connection);
int (*FB_AMDeviceSecureStartService)(AMDeviceRef device, CFStringRef service_name, _Nullable CFDictionaryRef userinfo, void *handle);
int (*FB_AMDeviceStartService)(AMDeviceRef device, CFStringRef service_name, void *handle, uint32_t *unknown);
int (*FB_AMDeviceSecureTransferPath)(int arg0, AMDeviceRef device, CFURLRef arg2, CFDictionaryRef arg3, void *_Nullable callback, void *_Nullable context);
int (*FB_AMDeviceSecureInstallApplication)(int arg0, AMDeviceRef device, CFURLRef arg2, CFDictionaryRef arg3, void *_Nullable callback, void *_Nullable context);
int (*FB_AMDeviceSecureUninstallApplication)(int arg0, AMDeviceRef device, CFStringRef arg2, int arg3, void *_Nullable callback, void *_Nullable context);
int (*FB_AMDeviceLookupApplications)(AMDeviceRef device, int arg1, CFDictionaryRef _Nonnull * _Nonnull arg2);

// Debugging
void (*FB_AMDSetLogLevel)(int32_t level);
_Nullable CFStringRef (*FB_AMDCopyErrorText)(int status);

#pragma mark - FBAMDevice Implementation

@implementation FBAMDevice

#pragma mark Initializers

+ (void)enableDebugLogging
{
  FB_AMDSetLogLevel(9);
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
  dispatch_queue_t workQueue = dispatch_get_main_queue();
  NSMutableArray<FBAMDevice *> *devices = [NSMutableArray array];
  CFArrayRef array = FB_AMDCreateDeviceList();
  for (NSInteger index = 0; index < CFArrayGetCount(array); index++) {
    CFTypeRef value = CFArrayGetValueAtIndex(array, index);
    FBAMDevice *device = [[FBAMDevice alloc] initWithAMDevice:value workQueue:workQueue];
    if (![device cacheAllValues]) {
      continue;
    }
    [devices addObject:device];
  }
  CFRelease(array);
  return [devices copy];
}

- (instancetype)initWithAMDevice:(AMDeviceRef)amDevice workQueue:(dispatch_queue_t)workQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _amDevice = CFRetain(amDevice);
  _workQueue = workQueue;

  return self;
}

#pragma mark Public Methods

- (FBFuture *)futureForDeviceOperation:(id(^)(AMDeviceRef, NSError **))block
{
  CFTypeRef amDevice = self.amDevice;
  return [FBFuture onQueue:self.workQueue resolve:^{
    int status = FB_AMDeviceConnect(amDevice);
    if (status != 0) {
      NSString *errorDescription = CFBridgingRelease(FB_AMDCopyErrorText(status));
      return [[FBDeviceControlError
        describeFormat:@"Failed to connect to device. (%@)", errorDescription]
        failFuture];
    }
    status = FB_AMDeviceStartSession(amDevice);
    if (status != 0) {
      FB_AMDeviceDisconnect(amDevice);
      NSString *errorDescription = CFBridgingRelease(FB_AMDCopyErrorText(status));
      return [[FBDeviceControlError
        describeFormat:@"Failed to start session with device. (%@)", errorDescription]
        failFuture];
    }
    NSError *error = nil;
    id result = block(amDevice, &error);
    FB_AMDeviceStopSession(amDevice);
    FB_AMDeviceDisconnect(amDevice);
    return result ? [FBFuture futureWithResult:result] : [FBFuture futureWithError:error];
  }];
}

- (id)handleWithBlockDeviceSession:(id(^)(AMDeviceRef))operationBlock error:(NSError **)error
{
  FBFuture<id> *future = [self futureForDeviceOperation:^(AMDeviceRef amDevice, NSError **innerError) {
    id result = operationBlock(amDevice);
    if (!result) {
      return [[FBDeviceControlError
        describe:@"Device Operation Failed"]
        fail:innerError];
    }
    return result;
  }];
  return [future await:error];
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
  return [[self handleWithBlockDeviceSession:^(AMDeviceRef device) {
    self->_udid = CFBridgingRelease(FB_AMDeviceCopyDeviceIdentifier(device));
    self->_deviceName = CFBridgingRelease(FB_AMDeviceCopyValue(device, NULL, CFSTR("DeviceName")));
    self->_modelName = CFBridgingRelease(FB_AMDeviceCopyValue(device, NULL, CFSTR("DeviceClass")));
    self->_systemVersion = CFBridgingRelease(FB_AMDeviceCopyValue(device, NULL, CFSTR("ProductVersion")));
    self->_productType = CFBridgingRelease(FB_AMDeviceCopyValue(device, NULL, CFSTR("ProductType")));
    self->_architecture = CFBridgingRelease(FB_AMDeviceCopyValue(device, NULL, CFSTR("CPUArchitecture")));

    NSString *osVersion = [FBAMDevice osVersionForDevice:device];
    self->_deviceConfiguration = FBControlCoreConfigurationVariants.productTypeToDevice[self->_productType];
    self->_osConfiguration = FBControlCoreConfigurationVariants.nameToOSVersion[osVersion] ?: [FBOSVersion genericWithName:osVersion];
    return @YES;
  } error:nil] boolValue];
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

@end

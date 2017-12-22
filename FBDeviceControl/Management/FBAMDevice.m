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

_Nullable CFArrayRef (*_Nonnull FB_AMDCreateDeviceList)(void);
int (*FB_AMDeviceConnect)(CFTypeRef device);
int (*FB_AMDeviceDisconnect)(CFTypeRef device);
int (*FB_AMDeviceIsPaired)(CFTypeRef device);
int (*FB_AMDeviceValidatePairing)(CFTypeRef device);
int (*FB_AMDeviceStartSession)(CFTypeRef device);
int (*FB_AMDeviceStopSession)(CFTypeRef device);
int (*FB_AMDServiceConnectionGetSocket)(CFTypeRef connection);
int (*FB_AMDServiceConnectionInvalidate)(CFTypeRef connection);
int (*FB_AMDeviceSecureStartService)(CFTypeRef device, CFStringRef service_name, _Nullable CFDictionaryRef userinfo, void *handle);
int (*FB_AMDeviceStartService)(CFTypeRef device, CFStringRef service_name, void *handle, uint32_t *unknown);
_Nullable CFStringRef (*_Nonnull FB_AMDeviceGetName)(CFTypeRef device);
_Nullable CFStringRef (*_Nonnull FB_AMDeviceCopyValue)(CFTypeRef device, _Nullable CFStringRef domain, CFStringRef name);
int (*FB_AMDeviceSecureTransferPath)(int arg0, CFTypeRef arg1, CFURLRef arg2, CFDictionaryRef arg3, void *_Nullable arg4, int arg5);
int (*FB_AMDeviceSecureInstallApplication)(int arg0, CFTypeRef arg1, CFURLRef arg2, CFDictionaryRef arg3,  void *_Nullable arg4, int arg5);
int (*FB_AMDeviceSecureUninstallApplication)(int arg0, CFTypeRef arg1, CFStringRef arg2, int arg3, void *_Nullable arg4, int arg5);
int (*FB_AMDeviceLookupApplications)(CFTypeRef arg0, int arg1, CFDictionaryRef *arg2);
void (*FB_AMDSetLogLevel)(int32_t level);

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
  FB_AMDSetLogLevel = (void(*)(int32_t))FBGetSymbolFromHandle(handle, "AMDSetLogLevel");
  FB_AMDeviceConnect = (int(*)(CFTypeRef device))FBGetSymbolFromHandle(handle, "AMDeviceConnect");
  FB_AMDeviceDisconnect = (int(*)(CFTypeRef device))FBGetSymbolFromHandle(handle, "AMDeviceDisconnect");
  FB_AMDeviceIsPaired = (int(*)(CFTypeRef device))FBGetSymbolFromHandle(handle, "AMDeviceIsPaired");
  FB_AMDeviceValidatePairing = (int(*)(CFTypeRef device))FBGetSymbolFromHandle(handle, "AMDeviceValidatePairing");
  FB_AMDeviceStartSession = (int(*)(CFTypeRef device))FBGetSymbolFromHandle(handle, "AMDeviceStartSession");
  FB_AMDeviceStopSession =  (int(*)(CFTypeRef device))FBGetSymbolFromHandle(handle, "AMDeviceStopSession");
  FB_AMDServiceConnectionGetSocket = (int(*)(CFTypeRef))FBGetSymbolFromHandle(handle, "AMDServiceConnectionGetSocket");
  FB_AMDServiceConnectionInvalidate = (int(*)(CFTypeRef))FBGetSymbolFromHandle(handle, "AMDServiceConnectionInvalidate");
  FB_AMDeviceSecureStartService = (int(*)(CFTypeRef, CFStringRef, CFDictionaryRef, void *))FBGetSymbolFromHandle(handle, "AMDeviceSecureStartService");
  FB_AMDeviceStartService = (int(*)(CFTypeRef, CFStringRef, void *, uint32_t *))FBGetSymbolFromHandle(handle, "AMDeviceStartService");
  FB_AMDCreateDeviceList = (CFArrayRef(*)(void))FBGetSymbolFromHandle(handle, "AMDCreateDeviceList");
  FB_AMDeviceGetName = (CFStringRef(*)(CFTypeRef))FBGetSymbolFromHandle(handle, "AMDeviceGetName");
  FB_AMDeviceCopyValue = (CFStringRef(*)(CFTypeRef, CFStringRef, CFStringRef))FBGetSymbolFromHandle(handle, "AMDeviceCopyValue");
  FB_AMDeviceSecureTransferPath = (int(*)(int, CFTypeRef, CFURLRef, CFDictionaryRef, void *, int))FBGetSymbolFromHandle(handle, "AMDeviceSecureTransferPath");
  FB_AMDeviceSecureInstallApplication = (int(*)(int, CFTypeRef, CFURLRef, CFDictionaryRef, void *, int))FBGetSymbolFromHandle(handle, "AMDeviceSecureInstallApplication");
  FB_AMDeviceSecureUninstallApplication = (int(*)(int, CFTypeRef, CFStringRef, int, void *, int))FBGetSymbolFromHandle(handle, "AMDeviceSecureUninstallApplication");
  FB_AMDeviceLookupApplications = (int(*)(CFTypeRef, int, CFDictionaryRef*))FBGetSymbolFromHandle(handle, "AMDeviceLookupApplications");
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

- (instancetype)initWithAMDevice:(CFTypeRef)amDevice workQueue:(dispatch_queue_t)workQueue
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

- (FBFuture *)futureForDeviceOperation:(id(^)(CFTypeRef, NSError **))block
{
  CFTypeRef amDevice = self.amDevice;
  return [FBFuture onQueue:self.workQueue resolve:^{
    if (FB_AMDeviceConnect(amDevice) != 0) {
      return [[FBDeviceControlError
        describe:@"Failed to connect to device."]
        failFuture];
    }
    if (FB_AMDeviceIsPaired(amDevice) != 1) {
      FB_AMDeviceDisconnect(amDevice);
      return [[FBDeviceControlError
        describe:@"Device is not paired"]
        failFuture];
    }
    if (FB_AMDeviceValidatePairing(amDevice) != 0) {
      FB_AMDeviceDisconnect(amDevice);
      return [[FBDeviceControlError
        describe:@"Validate pairing failed"]
        failFuture];
    }
    if (FB_AMDeviceStartSession(amDevice) != 0) {
      FB_AMDeviceDisconnect(amDevice);
      return [[FBDeviceControlError
        describe:@"Failed to start session with device."]
        failFuture];
    }
    NSError *error = nil;
    id result = block(amDevice, &error);
    FB_AMDeviceStopSession(amDevice);
    return result ? [FBFuture futureWithResult:result] : [FBFuture futureWithError:error];
  }];
}

- (id)handleWithBlockDeviceSession:(id(^)(CFTypeRef device))operationBlock error:(NSError **)error
{
  FBFuture<id> *future = [self futureForDeviceOperation:^(CFTypeRef amDevice, NSError **innerError) {
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

- (CFTypeRef)startService:(NSString *)service userInfo:(NSDictionary *)userInfo error:(NSError **)error
{
  return (__bridge CFTypeRef _Nonnull)([self handleWithBlockDeviceSession:^id(CFTypeRef device) {
    CFTypeRef test_apple_afc_conn;
    FB_AMDeviceSecureStartService(
      device,
      (__bridge CFStringRef _Nonnull)(service),
      (__bridge CFDictionaryRef _Nonnull)(userInfo),
      &test_apple_afc_conn
    );
    return (__bridge id)(test_apple_afc_conn);
  } error:error]);
}

- (CFTypeRef)startTestManagerServiceWithError:(NSError **)error
{
  NSDictionary *userInfo = @{
    @"CloseOnInvalidate" : @1,
    @"InvalidateOnDetach" : @1
  };
  return [self startService:@"com.apple.testmanagerd.lockdown" userInfo:userInfo error:error];
}

- (void)dealloc
{
  CFRelease(_amDevice);
}

#pragma mark Private

- (BOOL)cacheAllValues
{
  return
  [[self handleWithBlockDeviceSession:^id(CFTypeRef device) {
    self->_udid = (__bridge NSString *)(FB_AMDeviceGetName(device));
    self->_deviceName = (__bridge NSString *)(FB_AMDeviceCopyValue(device, NULL, CFSTR("DeviceName")));
    self->_modelName = (__bridge NSString *)(FB_AMDeviceCopyValue(device, NULL, CFSTR("DeviceClass")));
    self->_systemVersion = (__bridge NSString *)(FB_AMDeviceCopyValue(device, NULL, CFSTR("ProductVersion")));
    self->_productType = (__bridge NSString *)(FB_AMDeviceCopyValue(device, NULL, CFSTR("ProductType")));
    self->_architecture = (__bridge NSString *)(FB_AMDeviceCopyValue(device, NULL, CFSTR("CPUArchitecture")));

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

+ (NSString *)osVersionForDevice:(CFTypeRef)amDevice
{
  NSString *deviceClass = (__bridge NSString *)(FB_AMDeviceCopyValue(amDevice, NULL, CFSTR("DeviceClass")));
  NSString *productVersion = (__bridge NSString *)(FB_AMDeviceCopyValue(amDevice, NULL, CFSTR("ProductVersion")));
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

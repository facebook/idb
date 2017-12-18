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

_Nullable CFArrayRef (*_Nonnull FBAMDCreateDeviceList)(void);
int (*FBAMDeviceConnect)(CFTypeRef device);
int (*FBAMDeviceDisconnect)(CFTypeRef device);
int (*FBAMDeviceIsPaired)(CFTypeRef device);
int (*FBAMDeviceValidatePairing)(CFTypeRef device);
int (*FBAMDeviceStartSession)(CFTypeRef device);
int (*FBAMDeviceStopSession)(CFTypeRef device);
int (*FBAMDServiceConnectionGetSocket)(CFTypeRef connection);
int (*FBAMDServiceConnectionInvalidate)(CFTypeRef connection);
int (*FBAMDeviceSecureStartService)(CFTypeRef device, CFStringRef service_name, _Nullable CFDictionaryRef userinfo, void *handle);
int (*FBAMDeviceStartService)(CFTypeRef device, CFStringRef service_name, void *handle, uint32_t *unknown);
_Nullable CFStringRef (*_Nonnull FBAMDeviceGetName)(CFTypeRef device);
_Nullable CFStringRef (*_Nonnull FBAMDeviceCopyValue)(CFTypeRef device, _Nullable CFStringRef domain, CFStringRef name);
int (*FBAMDeviceSecureTransferPath)(int arg0, CFTypeRef arg1, CFURLRef arg2, CFDictionaryRef arg3, void *_Nullable arg4, int arg5);
int (*FBAMDeviceSecureInstallApplication)(int arg0, CFTypeRef arg1, CFURLRef arg2, CFDictionaryRef arg3,  void *_Nullable arg4, int arg5);
int (*FBAMDeviceSecureUninstallApplication)(int arg0, CFTypeRef arg1, CFStringRef arg2, int arg3, void *_Nullable arg4, int arg5);
int (*FBAMDeviceLookupApplications)(CFTypeRef arg0, int arg1, CFDictionaryRef *arg2);
void (*FBAMDSetLogLevel)(int32_t level);

@implementation FBAMDevice

#pragma mark Initializers

+ (void)enableDebugLogging
{
  FBAMDSetLogLevel(9);
}

+ (void)loadFBAMDeviceSymbols
{
  void *handle = dlopen("/System/Library/PrivateFrameworks/MobileDevice.framework/Versions/A/MobileDevice", RTLD_LAZY);
  NSCAssert(handle, @"MobileDevice could not be opened");
  FBAMDSetLogLevel = (void(*)(int32_t))FBGetSymbolFromHandle(handle, "AMDSetLogLevel");
  FBAMDeviceConnect = (int(*)(CFTypeRef device))FBGetSymbolFromHandle(handle, "AMDeviceConnect");
  FBAMDeviceDisconnect = (int(*)(CFTypeRef device))FBGetSymbolFromHandle(handle, "AMDeviceDisconnect");
  FBAMDeviceIsPaired = (int(*)(CFTypeRef device))FBGetSymbolFromHandle(handle, "AMDeviceIsPaired");
  FBAMDeviceValidatePairing = (int(*)(CFTypeRef device))FBGetSymbolFromHandle(handle, "AMDeviceValidatePairing");
  FBAMDeviceStartSession = (int(*)(CFTypeRef device))FBGetSymbolFromHandle(handle, "AMDeviceStartSession");
  FBAMDeviceStopSession =  (int(*)(CFTypeRef device))FBGetSymbolFromHandle(handle, "AMDeviceStopSession");
  FBAMDServiceConnectionGetSocket = (int(*)(CFTypeRef))FBGetSymbolFromHandle(handle, "AMDServiceConnectionGetSocket");
  FBAMDServiceConnectionInvalidate = (int(*)(CFTypeRef))FBGetSymbolFromHandle(handle, "AMDServiceConnectionInvalidate");
  FBAMDeviceSecureStartService = (int(*)(CFTypeRef, CFStringRef, CFDictionaryRef, void *))FBGetSymbolFromHandle(handle, "AMDeviceSecureStartService");
  FBAMDeviceStartService = (int(*)(CFTypeRef, CFStringRef, void *, uint32_t *))FBGetSymbolFromHandle(handle, "AMDeviceStartService");
  FBAMDCreateDeviceList = (CFArrayRef(*)(void))FBGetSymbolFromHandle(handle, "AMDCreateDeviceList");
  FBAMDeviceGetName = (CFStringRef(*)(CFTypeRef))FBGetSymbolFromHandle(handle, "AMDeviceGetName");
  FBAMDeviceCopyValue = (CFStringRef(*)(CFTypeRef, CFStringRef, CFStringRef))FBGetSymbolFromHandle(handle, "AMDeviceCopyValue");
  FBAMDeviceSecureTransferPath = (int(*)(int, CFTypeRef, CFURLRef, CFDictionaryRef, void *, int))FBGetSymbolFromHandle(handle, "AMDeviceSecureTransferPath");
  FBAMDeviceSecureInstallApplication = (int(*)(int, CFTypeRef, CFURLRef, CFDictionaryRef, void *, int))FBGetSymbolFromHandle(handle, "AMDeviceSecureInstallApplication");
  FBAMDeviceSecureUninstallApplication = (int(*)(int, CFTypeRef, CFStringRef, int, void *, int))FBGetSymbolFromHandle(handle, "AMDeviceSecureUninstallApplication");
  FBAMDeviceLookupApplications = (int(*)(CFTypeRef, int, CFDictionaryRef*))FBGetSymbolFromHandle(handle, "AMDeviceLookupApplications");
}
+ (NSArray<FBAMDevice *> *)allDevices
{
  NSMutableArray<FBAMDevice *> *devices = [NSMutableArray array];
  CFArrayRef array = FBAMDCreateDeviceList();
  for (NSInteger index = 0; index < CFArrayGetCount(array); index++) {
    CFTypeRef value = CFArrayGetValueAtIndex(array, index);
    FBAMDevice *device = [[FBAMDevice alloc] initWithAMDevice:value];
    if (![device cacheAllValues]) {
      continue;
    }
    [devices addObject:device];
  }
  CFRelease(array);
  return [devices copy];
}

- (instancetype)initWithAMDevice:(CFTypeRef)amDevice
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _amDevice = CFRetain(amDevice);

  return self;
}

#pragma mark Public Methods

- (FBFuture *)futureForDeviceOperation:(id(^)(CFTypeRef, NSError **))block
{
  if (FBAMDeviceConnect(_amDevice) != 0) {
    return [[FBDeviceControlError
      describe:@"Failed to connect to device."]
      failFuture];
  }
  if (FBAMDeviceIsPaired(_amDevice) != 1) {
    FBAMDeviceDisconnect(_amDevice);
    return [[FBDeviceControlError
      describe:@"Device is not paired"]
      failFuture];
  }
  if (FBAMDeviceValidatePairing(_amDevice) != 0) {
    FBAMDeviceDisconnect(_amDevice);
    return [[FBDeviceControlError
      describe:@"Validate pairing failed"]
      failFuture];
  }
  if (FBAMDeviceStartSession(_amDevice) != 0) {
    FBAMDeviceDisconnect(_amDevice);
    return [[FBDeviceControlError
      describe:@"Failed to start session with device."]
      failFuture];
  }
  NSError *error = nil;
  id result = block(_amDevice, &error);
  FBAMDeviceStopSession(_amDevice);
  return result
    ? [FBFuture futureWithResult:result]
    : [FBFuture futureWithError:error];
}

- (id)handleWithBlockDeviceSession:(id(^)(CFTypeRef device))operationBlock error:(NSError **)error
{
  FBFuture<id> *future= [self futureForDeviceOperation:^(CFTypeRef amDevice, NSError **innerError) {
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
    FBAMDeviceSecureStartService(
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
    self->_udid = (__bridge NSString *)(FBAMDeviceGetName(device));
    self->_deviceName = (__bridge NSString *)(FBAMDeviceCopyValue(device, NULL, CFSTR("DeviceName")));
    self->_modelName = (__bridge NSString *)(FBAMDeviceCopyValue(device, NULL, CFSTR("DeviceClass")));
    self->_systemVersion = (__bridge NSString *)(FBAMDeviceCopyValue(device, NULL, CFSTR("ProductVersion")));
    self->_productType = (__bridge NSString *)(FBAMDeviceCopyValue(device, NULL, CFSTR("ProductType")));
    self->_architecture = (__bridge NSString *)(FBAMDeviceCopyValue(device, NULL, CFSTR("CPUArchitecture")));

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
  NSString *deviceClass = (__bridge NSString *)(FBAMDeviceCopyValue(amDevice, NULL, CFSTR("DeviceClass")));
  NSString *productVersion = (__bridge NSString *)(FBAMDeviceCopyValue(amDevice, NULL, CFSTR("ProductVersion")));
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

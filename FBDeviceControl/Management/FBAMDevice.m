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

static void *FBGetSymbolFromHandle(void *handle, const char *name)
{
  void *function = dlsym(handle, name);
  NSCAssert(function, @"%s could not be located", name);
  return function;
}

@implementation FBAMDevice

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
  FBAMDCreateDeviceList = (CFArrayRef(*)(void))FBGetSymbolFromHandle(handle, "AMDCreateDeviceList");
  FBAMDeviceGetName = (CFStringRef(*)(CFTypeRef))FBGetSymbolFromHandle(handle, "AMDeviceGetName");
  FBAMDeviceCopyValue = (CFStringRef(*)(CFTypeRef, CFStringRef, CFStringRef))FBGetSymbolFromHandle(handle, "AMDeviceCopyValue");
  FBAMDeviceSecureTransferPath = (int(*)(int, CFTypeRef, CFURLRef, CFDictionaryRef, void *, int))FBGetSymbolFromHandle(handle, "AMDeviceSecureTransferPath");
  FBAMDeviceSecureInstallApplication = (int(*)(int, CFTypeRef, CFURLRef, CFDictionaryRef, void *, int))FBGetSymbolFromHandle(handle, "AMDeviceSecureInstallApplication");
  FBAMDeviceSecureUninstallApplication = (int(*)(int, CFTypeRef, CFStringRef, int, void *, int))FBGetSymbolFromHandle(handle, "AMDeviceSecureUninstallApplication");
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

- (id)handleWithBlockDeviceSession:(id(^)(CFTypeRef device))operationBlock error:(NSError **)error
{
  if (FBAMDeviceConnect(_amDevice) != 0) {
    return
    [[FBDeviceControlError
      describe:@"Failed to connect to device."]
     fail:error];
  }
  if (FBAMDeviceIsPaired(_amDevice) != 1) {
    return
    [[FBDeviceControlError
      describe:@"Device is not paired"]
     fail:error];
  }
  if (FBAMDeviceValidatePairing(_amDevice) != 0) {
    return
    [[FBDeviceControlError
      describe:@"Validate pairing failed"]
     fail:error];
  }
  id operationResult = nil;
  if (FBAMDeviceStartSession(_amDevice) == 0) {
    operationResult = operationBlock(_amDevice);
    FBAMDeviceStopSession(_amDevice);
  } else {
    [[FBDeviceControlError
      describe:@"Failed to start session with device."]
     fail:error];
  }
  FBAMDeviceDisconnect(_amDevice);
  return operationResult;
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

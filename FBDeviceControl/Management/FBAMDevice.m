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

static const char *MobileDeviceDylibPath = "/System/Library/PrivateFrameworks/MobileDevice.framework/Versions/A/MobileDevice";
static void *FBGetMobileDeviceFunction(const char *name)
{
  void *handle = dlopen(MobileDeviceDylibPath, RTLD_LAZY);
  NSCAssert(handle, @"MobileDevice could not be opened");
  void *function = dlsym(handle, name);
  NSCAssert(function, @"%s could not be located", name);
  return function;
}

void FBAMDSetLogLevel(int32_t level)
{
  void (*AMDSetLogLevel)(int32_t) = FBGetMobileDeviceFunction("AMDSetLogLevel");
  AMDSetLogLevel(level);
}

int FBAMDeviceConnect(CFTypeRef device)
{
  int (*Connect) (CFTypeRef device) = FBGetMobileDeviceFunction("AMDeviceConnect");
  return Connect(device);
}

int FBAMDeviceDisconnect(CFTypeRef device)
{
  int (*Disconnect) (CFTypeRef device) = FBGetMobileDeviceFunction("AMDeviceDisconnect");
  return Disconnect(device);
}

int FBAMDeviceIsPaired(CFTypeRef device)
{
  int (*IsPaired) (CFTypeRef device) = FBGetMobileDeviceFunction("AMDeviceIsPaired");
  return IsPaired(device);
}

int FBAMDeviceValidatePairing(CFTypeRef device)
{
  int (*ValidatePairing) (CFTypeRef device) = FBGetMobileDeviceFunction("AMDeviceValidatePairing");
  return ValidatePairing(device);
}

int FBAMDeviceStartSession(CFTypeRef device)
{
  int (*StartSession) (CFTypeRef device) = FBGetMobileDeviceFunction("AMDeviceStartSession");
  return StartSession(device);
}

int FBAMDeviceStopSession(CFTypeRef device)
{
  int (*StopSession) (CFTypeRef device) = FBGetMobileDeviceFunction("AMDeviceStopSession");
  return StopSession(device);
}

CFArrayRef FBAMDCreateDeviceList(void)
{
  CFArrayRef (*CreateDeviceList) (void) = FBGetMobileDeviceFunction("AMDCreateDeviceList");
  return CreateDeviceList();
}

CFStringRef FBAMDeviceGetName(CFTypeRef device)
{
  CFStringRef (*GetName) (CFTypeRef) = FBGetMobileDeviceFunction("AMDeviceGetName");
  return GetName(device);
}

CFStringRef FBAMDeviceCopyValue(CFTypeRef device, _Nullable CFStringRef domain, CFStringRef name)
{
  CFStringRef (*CopyValue) (CFTypeRef, CFStringRef, CFStringRef) = FBGetMobileDeviceFunction("AMDeviceCopyValue");
  return CopyValue(device, domain, name);
}

@implementation FBAMDevice

+ (void)enableDebugLogging
{
  FBAMDSetLogLevel(9);
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

- (void)dealloc
{
  CFRelease(_amDevice);
  _amDevice = nil;
}

#pragma mark Private

- (BOOL)cacheAllValues
{
  return
  [[self handleWithBlockDeviceSession:^id(CFTypeRef device) {
    if (FBAMDeviceIsPaired(device) != 1) {
      return @NO;

    }
    if (FBAMDeviceValidatePairing(device) != 0) {
      return @NO;
    }

    self->_udid = (__bridge NSString *)(FBAMDeviceGetName(device));
    self->_deviceName = (__bridge NSString *)(FBAMDeviceCopyValue(device, NULL, CFSTR("DeviceName")));
    self->_modelName = (__bridge NSString *)(FBAMDeviceCopyValue(device, NULL, CFSTR("DeviceClass")));
    self->_systemVersion = (__bridge NSString *)(FBAMDeviceCopyValue(device, NULL, CFSTR("ProductVersion")));
    self->_productType = (__bridge NSString *)(FBAMDeviceCopyValue(device, NULL, CFSTR("ProductType")));
    self->_architechture = (__bridge NSString *)(FBAMDeviceCopyValue(device, NULL, CFSTR("CPUArchitecture")));

    NSString *osVersion = [FBAMDevice osVersionForDevice:device];
    self->_deviceConfiguration = FBControlCoreConfigurationVariants.productTypeToDevice[self->_productType];
    self->_osConfiguration = FBControlCoreConfigurationVariants.nameToOSVersion[osVersion];
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

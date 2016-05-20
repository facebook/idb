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

static const char *MobileDeviceDylibPath = "/System/Library/PrivateFrameworks/MobileDevice.framework/Versions/A/MobileDevice";

static void *FBGetMobileDeviceFunction(const char *name)
{
  void *handle = dlopen(MobileDeviceDylibPath, RTLD_LAZY);
  NSCAssert(handle, @"MobileDevice could not be opened");
  void *function = dlsym(handle, name);
  NSCAssert(function, @"%s could not be located", name);
  return function;
}

static int FBAMDConnect(CFTypeRef device)
{
  int (*Connect) (CFTypeRef device) = FBGetMobileDeviceFunction("AMDeviceConnect");
  return Connect(device);
}

static int FBAMDDisconnect(CFTypeRef device)
{
  int (*Disconnect) (CFTypeRef device) = FBGetMobileDeviceFunction("AMDeviceDisconnect");
  return Disconnect(device);
}

static CFArrayRef FBAMDCreateDeviceList(void)
{
  CFArrayRef (*CreateDeviceList) (void) = FBGetMobileDeviceFunction("AMDCreateDeviceList");
  return CreateDeviceList();
}

static CFStringRef FBAMDGetName(CFTypeRef device)
{
  CFStringRef (*GetName) (CFTypeRef) = FBGetMobileDeviceFunction("AMDeviceGetName");
  return GetName(device);
}

static CFStringRef FBAMDGetValue(CFTypeRef device, CFStringRef domain, CFStringRef name)
{
  CFStringRef (*CopyValue) (CFTypeRef, CFStringRef, CFStringRef) = FBGetMobileDeviceFunction("AMDeviceCopyValue");
  return CopyValue(device, domain, name);
}

@implementation FBAMDevice

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

- (void)dealloc
{
  CFRelease(_amDevice);
  _amDevice = nil;
}

#pragma mark Private

- (BOOL)cacheAllValues
{
  if (FBAMDConnect(_amDevice) != 0) {
    return NO;
  }

  self.name = (__bridge NSString *)(FBAMDGetName(_amDevice));
  self.deviceName = (__bridge NSString *)(FBAMDGetValue(_amDevice, NULL, (__bridge CFStringRef) @"DeviceName"));

  FBAMDDisconnect(_amDevice);
  return YES;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"AMDevice %@ | %@",
    self.name,
    self.deviceName
  ];
}

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBDeviceControl/FBAMDevice.h>

NS_ASSUME_NONNULL_BEGIN

// Getting a full Device List
extern _Nullable CFArrayRef (*_Nonnull FB_AMDCreateDeviceList)(void);

// Managing a Connection to a Device
extern int (*FB_AMDeviceConnect)(CFTypeRef device);
extern int (*FB_AMDeviceDisconnect)(CFTypeRef device);
extern int (*FB_AMDeviceIsPaired)(CFTypeRef device);
extern int (*FB_AMDeviceValidatePairing)(CFTypeRef device);
extern int (*FB_AMDeviceStartSession)(CFTypeRef device);
extern int (*FB_AMDeviceStopSession)(CFTypeRef device);
extern int (*FB_AMDServiceConnectionGetSocket)(CFTypeRef connection);
extern int (*FB_AMDServiceConnectionInvalidate)(CFTypeRef connection);
extern int (*FB_AMDeviceSecureStartService)(CFTypeRef device, CFStringRef service_name, _Nullable CFDictionaryRef userinfo, void *handle);
extern int (*FB_AMDeviceStartService)(CFTypeRef device, CFStringRef service_name, void *handle, uint32_t *unknown);
extern int (*FB_AMDeviceSecureTransferPath)(int arg0, CFTypeRef arg1, CFURLRef arg2, CFDictionaryRef arg3, void *_Nullable arg4, int arg5);
extern int (*FB_AMDeviceSecureInstallApplication)(int arg0, CFTypeRef arg1, CFURLRef arg2, CFDictionaryRef arg3, void *_Nullable arg4, int arg5);
extern int (*FB_AMDeviceSecureUninstallApplication)(int arg0, CFTypeRef arg1, CFStringRef arg2, int arg3, void *_Nullable arg4, int arg5);
extern int (*FB_AMDeviceLookupApplications)(CFTypeRef arg0, int arg1, CFDictionaryRef _Nonnull * _Nonnull arg2);

// Getting Properties of a Device.
extern _Nullable CFStringRef (*_Nonnull FB_AMDeviceGetName)(CFTypeRef device);
extern _Nullable CFStringRef (*_Nonnull FB_AMDeviceCopyValue)(CFTypeRef device, _Nullable CFStringRef domain, CFStringRef name);

// Debugging
extern void (*FB_AMDSetLogLevel)(int32_t level);

@interface FBAMDevice ()

@property (nonatomic, assign, readonly) CFTypeRef amDevice;
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;

- (id)handleWithBlockDeviceSession:(id(^)(CFTypeRef device))operationBlock error:(NSError **)error;
- (CFTypeRef)startService:(NSString *)service userInfo:(NSDictionary *)userInfo error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

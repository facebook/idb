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
extern _Nullable CFArrayRef (*_Nonnull FBAMDCreateDeviceList)(void);

// Managing a Connection to a Device
extern int (*FBAMDeviceConnect)(CFTypeRef device);
extern int (*FBAMDeviceDisconnect)(CFTypeRef device);
extern int (*FBAMDeviceIsPaired)(CFTypeRef device);
extern int (*FBAMDeviceValidatePairing)(CFTypeRef device);
extern int (*FBAMDeviceStartSession)(CFTypeRef device);
extern int (*FBAMDeviceStopSession)(CFTypeRef device);
extern int (*FBAMDServiceConnectionGetSocket)(CFTypeRef connection);
extern int (*FBAMDServiceConnectionInvalidate)(CFTypeRef connection);
extern int (*FBAMDeviceSecureStartService)(CFTypeRef device, CFStringRef service_name, _Nullable CFDictionaryRef userinfo, void *handle);
extern int (*FBAMDeviceSecureTransferPath)(int arg0, CFTypeRef arg1, CFURLRef arg2, CFDictionaryRef arg3, void *_Nullable arg4, int arg5);
extern int (*FBAMDeviceSecureInstallApplication)(int arg0, CFTypeRef arg1, CFURLRef arg2, CFDictionaryRef arg3, void *_Nullable arg4, int arg5);
extern int (*FBAMDeviceSecureUninstallApplication)(int arg0, CFTypeRef arg1, CFStringRef arg2, int arg3, void *_Nullable arg4, int arg5);

// Getting Properties of a Device.
extern _Nullable CFStringRef (*_Nonnull FBAMDeviceGetName)(CFTypeRef device);
extern _Nullable CFStringRef (*_Nonnull FBAMDeviceCopyValue)(CFTypeRef device, _Nullable CFStringRef domain, CFStringRef name);

// Debugging
extern void (*FBAMDSetLogLevel)(int32_t level);

@interface FBAMDevice ()

@property (nonatomic, assign, readonly) CFTypeRef amDevice;

- (id)handleWithBlockDeviceSession:(id(^)(CFTypeRef device))operationBlock error:(NSError **)error;
- (CFTypeRef)startService:(NSString *)service userInfo:(NSDictionary *)userInfo error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

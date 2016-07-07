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
_Nullable CFArrayRef (*_Nonnull FBAMDCreateDeviceList)(void);

// Managing a Connection to a Device
int (*FBAMDeviceConnect)(CFTypeRef device);
int (*FBAMDeviceDisconnect)(CFTypeRef device);
int (*FBAMDeviceIsPaired)(CFTypeRef device);
int (*FBAMDeviceValidatePairing)(CFTypeRef device);
int (*FBAMDeviceStartSession)(CFTypeRef device);
int (*FBAMDeviceStopSession)(CFTypeRef device);
int (*FBAMDServiceConnectionGetSocket)(CFTypeRef connection);
int (*FBAMDServiceConnectionInvalidate)(CFTypeRef connection);
int (*FBAMDeviceSecureStartService)(CFTypeRef device, CFStringRef service_name, CFDictionaryRef userinfo, void *handle);

// Getting Properties of a Device.
_Nullable CFStringRef (*_Nonnull FBAMDeviceGetName)(CFTypeRef device);
_Nullable CFStringRef (*_Nonnull FBAMDeviceCopyValue)(CFTypeRef device, _Nullable CFStringRef domain, CFStringRef name);

// Debugging
void (*FBAMDSetLogLevel)(int32_t level);

@interface FBAMDevice ()

@property (nonatomic, assign, readonly) CFTypeRef amDevice;

@end

NS_ASSUME_NONNULL_END

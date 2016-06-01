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
CF_RETURNS_RETAINED CFArrayRef FBAMDCreateDeviceList(void);

// Managing a Connection to a Device
int FBAMDeviceConnect(CFTypeRef device);
int FBAMDeviceDisconnect(CFTypeRef device);
int FBAMDeviceIsPaired(CFTypeRef device);
int FBAMDeviceValidatePairing(CFTypeRef device);
int FBAMDeviceStartSession(CFTypeRef device);
int FBAMDeviceStopSession(CFTypeRef device);

// Getting Properties of a Device.
CFStringRef FBAMDeviceGetName(CFTypeRef device);
CFStringRef FBAMDeviceCopyValue(CFTypeRef device, _Nullable CFStringRef domain, CFStringRef name);

@interface FBAMDevice ()

@property (nonatomic, assign, readonly) CFTypeRef amDevice;

@end

NS_ASSUME_NONNULL_END

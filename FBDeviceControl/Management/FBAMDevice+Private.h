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

#pragma mark - Notifications

/**
 Notification for the Attachment of a Device.
 */
extern NSNotificationName const FBAMDeviceNotificationNameDeviceAttached;

/**
 Notification for the Detachment of a Device.
 */
extern NSNotificationName const FBAMDeviceNotificationNameDeviceDetached;

#pragma mark - AMDevice API

/**
 An Alias for where AMDevices are used in the AMDevice APIs.
 */
typedef CFTypeRef AMDeviceRef;

// Using Connections
extern int (*FB_AMDServiceConnectionGetSocket)(CFTypeRef connection);
extern int (*FB_AMDServiceConnectionInvalidate)(CFTypeRef connection);
extern int (*FB_AMDeviceSecureStartService)(AMDeviceRef device, CFStringRef service_name, _Nullable CFDictionaryRef userinfo, void *handle);
extern int (*FB_AMDeviceStartService)(AMDeviceRef device, CFStringRef service_name, void *handle, uint32_t *unknown);
extern int (*FB_AMDeviceSecureTransferPath)(int arg0, AMDeviceRef device, CFURLRef arg2, CFDictionaryRef arg3, void *_Nullable callback, void *_Nullable context);
extern int (*FB_AMDeviceSecureInstallApplication)(int arg0, AMDeviceRef device, CFURLRef arg2, CFDictionaryRef arg3, void *_Nullable callback, void *_Nullable context);
extern int (*FB_AMDeviceSecureUninstallApplication)(int arg0, AMDeviceRef device, CFStringRef arg2, int arg3, void *_Nullable callback, void *_Nullable context);
extern int (*FB_AMDeviceLookupApplications)(AMDeviceRef device, CFDictionaryRef _Nullable options, CFDictionaryRef _Nonnull * _Nonnull attributesOut);

// Debugging
extern _Nullable CFStringRef (* _Nonnull FB_AMDCopyErrorText)(int status);

#pragma mark - AMDevice Class Private

@interface FBAMDevice ()

#pragma mark Properties

/**
 The AMDevice Reference.
 May dissapear if the AMDevice is no longer valid.
 */
@property (nonatomic, assign, readwrite) AMDeviceRef amDevice;

/**
 The Queue on which work should be performed.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;

#pragma mark Private Methods

/**
 The Designated Initializer

 @param udid the UDID of the AMDevice
 @param workQueue the queue to perform work on.
 */
- (instancetype)initWithUDID:(NSString *)udid workQueue:(dispatch_queue_t)workQueue;

/**
 Build a Future from an operation for performing on a device.

 @param block the block to execute for the device.
 @return a Future that resolves with the result of the block.
 */
- (FBFuture *)futureForDeviceOperation:(id(^)(AMDeviceRef, NSError **))block;

/**
 Starts test manager daemon service
 */
- (FBFuture<NSValue *> *)startTestManagerService;

/**
 Starts a Service on the AMDevice.

 @param service the service name
 @param userInfo the userInfo for the service.
 @return a CFType wrapping the connection.
 */
- (FBFuture<NSValue *> *)startService:(NSString *)service userInfo:(NSDictionary *)userInfo;

@end

NS_ASSUME_NONNULL_END

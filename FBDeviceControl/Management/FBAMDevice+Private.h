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
extern int (*FB_AMDeviceLookupApplications)(AMDeviceRef device, int arg1, CFDictionaryRef _Nonnull * _Nonnull arg2);

#pragma mark - AMDevice Class Private

@interface FBAMDevice ()

#pragma mark Properties

/**
 The AMDevice Reference.
 */
@property (nonatomic, assign, readonly) AMDeviceRef amDevice;

/**
 The Queue on which work should be performed.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;

#pragma mark Private Methods

/**
 Build a Future from an operation for performing on a device.

 @param block the block to execute for the device.
 @return a Future that resolves with the result of the block.
 */
- (FBFuture *)futureForDeviceOperation:(id(^)(AMDeviceRef, NSError **))block;

/**
 Starts test manager daemon service

 @return AMDServiceConnection if the operation succeeds, otherwise NULL.
 */
- (CFTypeRef)startTestManagerServiceWithError:(NSError **)error;

/**
 Performs the Operation Block for the AMDeviceRef, failing if the value returned in the operationBlock is nil.

 @param operationBlock the block to perform.
 @param error an error out if the operationBlock returns nil.
 @return the value from the operationBlock.
 */
- (id)handleWithBlockDeviceSession:(id(^)(AMDeviceRef device))operationBlock error:(NSError **)error;

/**
 Starts a Service on the AMDevice.

 @param service the service name
 @param userInfo the userInfo for the service.
 @param error an error out for any error that occurs.
 @reutrn a CFType wrapping the connection.
 */
- (CFTypeRef)startService:(NSString *)service userInfo:(NSDictionary *)userInfo error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

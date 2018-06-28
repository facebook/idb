/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBDeviceControl/FBAMDevice.h>

#import "FBAFCConnection.h"

#pragma mark - AMDevice API

/**
 An Alias for where AMDevices are used in the AMDevice APIs.
 */
typedef CFTypeRef AMDeviceRef;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

/**
 A structure that contains references for all the AMDevice calls we use.
 */
typedef struct {
  // Managing Connections & Sessions.
  int (*Connect)(AMDeviceRef device);
  int (*Disconnect)(AMDeviceRef device);
  int (*IsPaired)(AMDeviceRef device);
  int (*ValidatePairing)(AMDeviceRef device);
  int (*StartSession)(AMDeviceRef device);
  int (*StopSession)(AMDeviceRef device);

  // Memory Management
  void (*Retain)(AMDeviceRef device);
  void (*Release)(AMDeviceRef device);

  // Getting Properties of a Device.
  _Nullable CFStringRef (*_Nonnull CopyDeviceIdentifier)(AMDeviceRef device);
  _Nullable CFStringRef (*_Nonnull CopyValue)(AMDeviceRef device, _Nullable CFStringRef domain, CFStringRef name);

  // Obtaining Devices.
  _Nullable CFArrayRef (*_Nonnull CreateDeviceList)(void);
  int (*NotificationSubscribe)(void *callback, int arg0, int arg1, void *context, void **subscriptionOut);
  int (*NotificationUnsubscribe)(void *subscription);

  // Using Connections.
  int (*ServiceConnectionGetSocket)(CFTypeRef connection);
  int (*ServiceConnectionInvalidate)(CFTypeRef connection);
  int (*ServiceConnectionReceive)(CFTypeRef connection, void *buffer, size_t bytes);
  int (*ServiceConnectionGetSecureIOContext)(CFTypeRef connection);
  int (*SecureStartService)(AMDeviceRef device, CFStringRef service_name, _Nullable CFDictionaryRef userinfo, CFTypeRef *serviceOut);
  int (*SecureTransferPath)(int arg0, AMDeviceRef device, CFURLRef arg2, CFDictionaryRef arg3, void *_Nullable callback, void *_Nullable context);
  int (*SecureInstallApplication)(int arg0, AMDeviceRef device, CFURLRef arg2, CFDictionaryRef arg3, void *_Nullable callback, void *_Nullable context);
  int (*SecureUninstallApplication)(int arg0, AMDeviceRef device, CFStringRef arg2, int arg3, void *_Nullable callback, void *_Nullable context);
  int (*LookupApplications)(AMDeviceRef device, CFDictionaryRef _Nullable options, CFDictionaryRef _Nonnull * _Nonnull attributesOut);
  int (*CreateHouseArrestService)(AMDeviceRef device, CFStringRef bundleID, void *_Nullable unused, AFCConnectionRef *connectionOut);

  // Debugging
  void (*SetLogLevel)(int32_t level);
  _Nullable CFStringRef (*CopyErrorText)(int status);
} AMDCalls;

#pragma clang diagnostic pop

NS_ASSUME_NONNULL_BEGIN

@class FBAMDServiceConnection;

#pragma mark - Notifications

/**
 Notification for the Attachment of a Device.
 */
extern NSNotificationName const FBAMDeviceNotificationNameDeviceAttached;

/**
 Notification for the Detachment of a Device.
 */
extern NSNotificationName const FBAMDeviceNotificationNameDeviceDetached;

#pragma mark - AMDevice Class Private

@interface FBAMDevice () <FBFutureContextManagerDelegate>

#pragma mark Properties

/**
 The AMDevice Reference
 */
@property (nonatomic, assign, readwrite) AMDeviceRef amDevice;

/**
 The Context Manager for the Connection
 */
@property (nonatomic, strong, readonly) FBFutureContextManager<FBAMDevice *> *connectionContextManager;

/**
 The AMDCalls to be used.
 */
@property (nonatomic, assign, readonly) AMDCalls calls;

/**
 The Queue on which work should be performed.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;

/**
 The logger to log to.
 */
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

/**
 The default AMDevice calls.
 */
@property (nonatomic, assign, readonly, class) AMDCalls defaultCalls;

#pragma mark Private Methods

/**
 The Designated Initializer

 @param udid the UDID of the AMDevice.
 @param calls the calls to use.
 @param connectionReuseTimeout the time to wait before releasing a connection
 @param workQueue the queue to perform work on.
 @param logger the logger to use.
 @return a new FBAMDevice instance.
 */
- (instancetype)initWithUDID:(NSString *)udid calls:(AMDCalls)calls connectionReuseTimeout:(nullable NSNumber *)connectionReuseTimeout workQueue:(dispatch_queue_t)workQueue logger:(id<FBControlCoreLogger>)logger;

/**
 Obtain the connection for a device.

 @param format the purpose of the connection
 @return a connection wrapped in an async context.
 */
- (FBFutureContext<FBAMDevice *> *)connectToDeviceWithPurpose:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

/**
 Starts test manager daemon service
 */
- (FBFutureContext<FBAMDServiceConnection *> *)startTestManagerService;

/**
 Starts a Service on the AMDevice.

 @param service the service name
 @param userInfo the userInfo for the service.
 @return a Future wrapping the FBAFCConnection.
 */
- (FBFutureContext<FBAMDServiceConnection *> *)startService:(NSString *)service userInfo:(NSDictionary *)userInfo;

/**
 Starts an AFC Session on the Device.

 @return a Future wrapping the AFC connection.
 */
- (FBFutureContext<FBAMDServiceConnection *> *)startAFCService;

/**
 Starts house arrest for a given bundle id.

 @param bundleID the bundle id to use.
 @param afcCalls the AFC calls to inject
 @return a Future context wrapping the AFC Connection.
 */
- (FBFutureContext<FBAFCConnection *> *)houseArrestAFCConnectionForBundleID:(NSString *)bundleID afcCalls:(AFCCalls)afcCalls;

@end

NS_ASSUME_NONNULL_END

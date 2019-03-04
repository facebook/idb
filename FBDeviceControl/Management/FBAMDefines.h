/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#pragma mark - AMDevice API

/**
 An Alias for where AMDevices are used in the AMDevice APIs.
 */
typedef CFTypeRef AMDeviceRef;

/**
 The Connection Reference as is typically passed around between functions.
 */
typedef CFTypeRef AFCConnectionRef;

/**
 An opaque handle to a notification subscription.
 */
typedef void *AMDNotificationSubscription;

/**
 An enum for read modes.
 */
typedef enum : uint64_t {
  FBAFCReadOnlyMode = 1,
  FBAFCreateReadAndWrite = 3
} FBAFCReadMode;

/**
 AMDevice Notification Types.
 */
typedef NS_ENUM(int, AMDeviceNotificationType) {
  AMDeviceNotificationTypeConnected = 1,
  AMDeviceNotificationTypeDisconnected = 2,
};

/**
 A Notification structure.
 */
typedef struct {
  AMDeviceRef _Nonnull amDevice;
  AMDeviceNotificationType status;
} AMDeviceNotification;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

/**
 Defines the "Progress Callback" function signature.
 */
typedef void (*AMDeviceProgressCallback)(NSDictionary<NSString *, id> *progress, void *_Nullable context);

/**
 Defines the "Notification Callback" function signature.
 */
typedef void (*AMDeviceNotificationCallback)(AMDeviceNotification *notification, void *_Nullable context);

/**
 A Structure that references to the AMDevice APIs we use.
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
  int (*NotificationSubscribe)(AMDeviceNotificationCallback callback, int arg0, int arg1, void *context, AMDNotificationSubscription *subscriptionOut);
  int (*NotificationUnsubscribe)(AMDNotificationSubscription subscription);

  // Using Connections.
  int (*ServiceConnectionGetSocket)(CFTypeRef connection);
  int (*ServiceConnectionInvalidate)(CFTypeRef connection);
  int (*ServiceConnectionReceive)(CFTypeRef connection, void *buffer, size_t bytes);
  int (*ServiceConnectionSend)(CFTypeRef connection, void *buffer, size_t bytes);
  int (*ServiceConnectionGetSecureIOContext)(CFTypeRef connection);

  // Services
  int (*SecureStartService)(AMDeviceRef device, CFStringRef service_name, _Nullable CFDictionaryRef userinfo, CFTypeRef *serviceOut);
  int (*SecureTransferPath)(int arg0, AMDeviceRef device, CFURLRef arg2, CFDictionaryRef arg3, _Nullable AMDeviceProgressCallback callback, void *_Nullable context);
  int (*SecureInstallApplication)(int arg0, AMDeviceRef device, CFURLRef arg2, CFDictionaryRef arg3, _Nullable AMDeviceProgressCallback callback, void *_Nullable context);
  int (*SecureUninstallApplication)(int arg0, AMDeviceRef device, CFStringRef arg2, int arg3, _Nullable AMDeviceProgressCallback callback, void *_Nullable context);
  int (*LookupApplications)(AMDeviceRef device, CFDictionaryRef _Nullable options, CFDictionaryRef _Nonnull * _Nonnull attributesOut);
  int (*CreateHouseArrestService)(AMDeviceRef device, CFStringRef bundleID, void *_Nullable unused, AFCConnectionRef *connectionOut);

  // Developer Images
  int (*MountImage)(AMDeviceRef device, CFStringRef image, CFDictionaryRef options, _Nullable AMDeviceProgressCallback callback, void *_Nullable context);

  // Debugging
  void (*SetLogLevel)(int32_t level);
  _Nullable CFStringRef (*CopyErrorText)(int status);
} AMDCalls;

/**
 A Structure holding references to the 'Apple File Conduit' APIs we use.
 */
typedef struct {
  // Creating a Connection
  AFCConnectionRef (*Create)(void *_Nullable unknown0, int socket, void *_Nullable unknown1, void *_Nullable unknown2, void *_Nullable unknown3);
  int (*ConnectionOpen)(CFTypeRef handle, uint32_t io_timeout,CFTypeRef _Nullable *_Nullable conn);
  int (*ConnectionClose)(AFCConnectionRef connection);
  int (*SetSecureContext)(CFTypeRef connection);

  // Individual Operations
  int (*DirectoryOpen)(AFCConnectionRef connection, const char *path, CFTypeRef _Nullable * _Nullable dir);
  int (*DirectoryRead)(AFCConnectionRef connection, CFTypeRef dir, char *_Nullable*_Nullable dirent);
  int (*DirectoryClose)(AFCConnectionRef connection, CFTypeRef dir);
  int (*DirectoryCreate)(AFCConnectionRef connection, const char *dir);
  int (*FileRefOpen)(AFCConnectionRef connection, const char *_Nonnull path, FBAFCReadMode mode, CFTypeRef *_Nonnull ref);
  int (*FileRefClose)(AFCConnectionRef connection, CFTypeRef ref);
  int (*FileRefSeek)(AFCConnectionRef connection, CFTypeRef ref, int64_t offset, uint64_t mode);
  int (*FileRefTell)(AFCConnectionRef connection, CFTypeRef ref, uint64_t *_Nonnull offset);
  int (*FileRefRead)(AFCConnectionRef connection, CFTypeRef ref, void *_Nonnull buf, uint64_t *_Nonnull len);
  int (*FileRefWrite)(AFCConnectionRef connection, CFTypeRef ref, const void *_Nonnull buf, uint64_t len);
  int (*RenamePath)(AFCConnectionRef connection, const char *_Nonnull path, const char *_Nonnull toPath);
  int (*RemovePath)(AFCConnectionRef connection, const char *_Nonnull path);

  // Batch Operations
  int (*ConnectionProcessOperation)(AFCConnectionRef connection, CFTypeRef operation);
  int (*OperationGetResultStatus)(CFTypeRef operation);
  CFTypeRef (*OperationCreateRemovePathAndContents)(CFTypeRef allocator, CFStringRef path, void *_Nullable unknown_callback_maybe);
  CFTypeRef (*OperationGetResultObject)(CFTypeRef operation);

  // Errors
  char *(*ErrorString)(int errorCode);
  CFDictionaryRef (*ConnectionCopyLastErrorInfo)(AFCConnectionRef connection);
} AFCCalls;

#pragma clang diagnostic pop

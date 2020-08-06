/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBAMDefines.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAFCConnection;
@class FBAMDServiceConnection;
@class FBDeveloperDiskImage;
@class FBDeviceLinkClient;

/**
 Defines properties that are required on classes related to the implementation of FBDevice.
 */
@protocol FBDevice <NSObject>

/**
 The AMDevice Calls to use.
 */
@property (nonatomic, assign, readonly) AMDCalls calls;

/**
 The underlying AMDeviceRef.
 This may be NULL.
 */
@property (nonatomic, assign, readonly) AMDeviceRef amDeviceRef;

/**
 The Device's Logger.
 */
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

/**
 The Device's 'Product Version'.
 */
@property (nonatomic, nullable, copy, readonly) NSString *productVersion;

/**
 The Device's 'Build Version'.
 */
@property (nonatomic, nullable, copy, readonly) NSString *buildVersion;

/**
 All of the Device Values available.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *allValues;

@end

/**
 Defines Device-Specific commands, off which others are based.
 */
@protocol FBDeviceCommands <FBDevice>

/**
 Obtain the connection for a device.

 @param format the purpose of the connection
 @return a connection wrapped in an async context.
 */
- (FBFutureContext<id<FBDeviceCommands>> *)connectToDeviceWithPurpose:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

/**
 Starts a Service on the AMDevice.

 @param service the service name
 @return a Future wrapping the FBAFCConnection.
 */
- (FBFutureContext<FBAMDServiceConnection *> *)startService:(NSString *)service;

/**
 Starts a Service, wrapping it in a "Device Link" Plist client.

 @param service the service name.
 @return a Future context wrapping the FBDeviceLinkClient.
 */
- (FBFutureContext<FBDeviceLinkClient *> *)startDeviceLinkService:(NSString *)service;

/**
 Starts a Service, wrapping it in an "AFC" Client.

 @param service the service name.
 @return a Future wrapping the AFC connection.
 */
- (FBFutureContext<FBAFCConnection *> *)startAFCService:(NSString *)service;

/**
 Starts house arrest for a given bundle id.

 @param bundleID the bundle id to use.
 @param afcCalls the AFC calls to inject
 @return a Future context wrapping the AFC Connection.
 */
- (FBFutureContext<FBAFCConnection *> *)houseArrestAFCConnectionForBundleID:(NSString *)bundleID afcCalls:(AFCCalls)afcCalls;

/**
 Mounts the developer disk image.

 @return a Future wrapping the mounted image.
 */
- (FBFuture<FBDeveloperDiskImage *> *)mountDeveloperDiskImage;

@end

NS_ASSUME_NONNULL_END

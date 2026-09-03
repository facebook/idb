/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBAMDefines.h>

@class FBAFCConnection;
@class FBAMDServiceConnection;
@class FBDeveloperDiskImage;
@class FBDeviceLinkClient;

/**
 Defines properties that are required on classes related to the implementation of FBDevice.
 */
@protocol FBDeviceProtocol <NSObject>

/**
 The AMDevice Calls to use.
 */
@property (nonatomic, readonly, assign) AMDCalls calls;

/**
 The underlying AMDeviceRef.
 This may be NULL.
 */
@property (nullable, nonatomic, readonly, assign) AMDeviceRef amDeviceRef;

/**
 The underlying AMRecoveryModeDeviceRef if in recovery.
 This may be NULL.
 */
@property (nullable, nonatomic, readonly, assign) AMRecoveryModeDeviceRef recoveryModeDeviceRef;

/**
 The Device's Logger.
 */
@property (nonnull, nonatomic, readonly, strong) id<FBControlCoreLogger> logger;

/**
 The Device's 'Product Version'.
 */
@property (nullable, nonatomic, readonly, copy) NSString *productVersion;

/**
 The Device's 'Build Version'.
 */
@property (nullable, nonatomic, readonly, copy) NSString *buildVersion;

/**
 The Device's 'Activation State'.
 */
@property (nonnull, nonatomic, readonly, copy) NSString *activationState;

/**
 All of the Device Values available.
 */
@property (nonnull, nonatomic, readonly, copy) NSDictionary<NSString *, id> *allValues;

@end

/**
 Defines Device-Specific commands, off which others are based.
 */
@protocol FBDeviceCommands <FBDeviceProtocol>

/**
 Obtain the connection for a device.

 @param purpose the purpose of the connection
 @return a connection wrapped in an async context.
 */
- (nonnull FBFutureContext<id<FBDeviceCommands>> *)connectToDeviceWithPurpose:(nonnull NSString *)purpose;

/**
 Starts a Service on the AMDevice.

 @param service the service name
 @return a Future wrapping the FBAMDServiceConnection.
 */
- (nonnull FBFutureContext<FBAMDServiceConnection *> *)startService:(nonnull NSString *)service;

/**
 Starts house arrest for a given bundle id.

 @param bundleID the bundle id to use.
 @param afcCalls the AFC calls to inject
 @return a Future context wrapping the AFC Connection.
 */
- (nonnull FBFutureContext<FBAFCConnection *> *)houseArrestAFCConnectionForBundleID:(nonnull NSString *)bundleID afcCalls:(AFCCalls)afcCalls;

@end

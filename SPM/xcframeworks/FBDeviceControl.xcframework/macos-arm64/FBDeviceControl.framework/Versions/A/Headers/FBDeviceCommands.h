/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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
 An enum representing the activation state of the device.
 */
typedef NSString *FBDeviceActivationState NS_STRING_ENUM;
extern FBDeviceActivationState const FBDeviceActivationStateUnknown;
extern FBDeviceActivationState const FBDeviceActivationStateUnactivated;
extern FBDeviceActivationState const FBDeviceActivationStateActivated;

/**
 A string enum representing keys within device information.
 */
typedef NSString *FBDeviceKey NS_STRING_ENUM;
extern FBDeviceKey const FBDeviceKeyChipID;
extern FBDeviceKey const FBDeviceKeyDeviceClass;
extern FBDeviceKey const FBDeviceKeyDeviceName;
extern FBDeviceKey const FBDeviceKeyLocationID;
extern FBDeviceKey const FBDeviceKeyProductType;
extern FBDeviceKey const FBDeviceKeySerialNumber;
extern FBDeviceKey const FBDeviceKeyUniqueChipID;
extern FBDeviceKey const FBDeviceKeyUniqueDeviceID;
extern FBDeviceKey const FBDeviceKeyCPUArchitecture;
extern FBDeviceKey const FBDeviceKeyBuildVersion;
extern FBDeviceKey const FBDeviceKeyProductVersion;
extern FBDeviceKey const FBDeviceKeyActivationState;
extern FBDeviceKey const FBDeviceKeyIsPaired;

/**
 Coerce an Activation State string to the String Enum

 @param activationState the string representation of the activation state.
 @return a FBDeviceActivationState string enum.
 */
extern FBDeviceActivationState FBDeviceActivationStateCoerceFromString(NSString *activationState);

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
@property (nonatomic, nullable, assign, readonly) AMDeviceRef amDeviceRef;

/**
 The underlying AMRecoveryModeDeviceRef if in recovery.
 This may be NULL.
 */
@property (nonatomic, nullable, assign, readonly) AMRecoveryModeDeviceRef recoveryModeDeviceRef;

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
 The Device's 'Activation State'.
 */
@property (nonatomic, assign, readonly) FBDeviceActivationState activationState;

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

@end

NS_ASSUME_NONNULL_END

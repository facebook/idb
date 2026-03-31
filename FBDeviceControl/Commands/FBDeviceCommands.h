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
 An enum representing the activation state of the device.
 */
typedef NSString *FBDeviceActivationState NS_STRING_ENUM;
extern FBDeviceActivationState _Nonnull const FBDeviceActivationStateUnknown;
extern FBDeviceActivationState _Nonnull const FBDeviceActivationStateUnactivated;
extern FBDeviceActivationState _Nonnull const FBDeviceActivationStateActivated;

/**
 A string enum representing keys within device information.
 */
typedef NSString *FBDeviceKey NS_STRING_ENUM;
extern FBDeviceKey _Nonnull const FBDeviceKeyChipID;
extern FBDeviceKey _Nonnull const FBDeviceKeyDeviceClass;
extern FBDeviceKey _Nonnull const FBDeviceKeyDeviceName;
extern FBDeviceKey _Nonnull const FBDeviceKeyLocationID;
extern FBDeviceKey _Nonnull const FBDeviceKeyProductType;
extern FBDeviceKey _Nonnull const FBDeviceKeySerialNumber;
extern FBDeviceKey _Nonnull const FBDeviceKeyUniqueChipID;
extern FBDeviceKey _Nonnull const FBDeviceKeyUniqueDeviceID;
extern FBDeviceKey _Nonnull const FBDeviceKeyCPUArchitecture;
extern FBDeviceKey _Nonnull const FBDeviceKeyBuildVersion;
extern FBDeviceKey _Nonnull const FBDeviceKeyProductVersion;
extern FBDeviceKey _Nonnull const FBDeviceKeyActivationState;
extern FBDeviceKey _Nonnull const FBDeviceKeyIsPaired;

/**
 Coerce an Activation State string to the String Enum

 @param activationState the string representation of the activation state.
 @return a FBDeviceActivationState string enum.
 */
extern FBDeviceActivationState _Nonnull FBDeviceActivationStateCoerceFromString(NSString * _Nonnull activationState);

/**
 Defines properties that are required on classes related to the implementation of FBDevice.
 */
@protocol FBDevice <NSObject>

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
@property (nonnull, nonatomic, readonly, assign) FBDeviceActivationState activationState;

/**
 All of the Device Values available.
 */
@property (nonnull, nonatomic, readonly, copy) NSDictionary<NSString *, id> *allValues;

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
- (nonnull FBFutureContext<id<FBDeviceCommands>> *)connectToDeviceWithPurpose:(nonnull NSString *)purpose;

/**
 Starts a Service on the AMDevice.

 @param service the service name
 @return a Future wrapping the FBAMDServiceConnection.
 */
- (nonnull FBFutureContext<FBAMDServiceConnection *> *)startService:(nonnull NSString *)service;

/**
 Starts a Service, wrapping it in a "Device Link" Plist client.

 @param service the service name.
 @return a Future context wrapping the FBDeviceLinkClient.
 */
- (nonnull FBFutureContext<FBDeviceLinkClient *> *)startDeviceLinkService:(nonnull NSString *)service;

/**
 Starts a Service, wrapping it in an "AFC" Client.

 @param service the service name.
 @return a Future wrapping the AFC connection.
 */
- (nonnull FBFutureContext<FBAFCConnection *> *)startAFCService:(nonnull NSString *)service;

/**
 Starts house arrest for a given bundle id.

 @param bundleID the bundle id to use.
 @param afcCalls the AFC calls to inject
 @return a Future context wrapping the AFC Connection.
 */
- (nonnull FBFutureContext<FBAFCConnection *> *)houseArrestAFCConnectionForBundleID:(nonnull NSString *)bundleID afcCalls:(AFCCalls)afcCalls;

@end

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBAMDefines.h>
#import <FBDeviceControl/FBDeviceStorage.h>

NS_ASSUME_NONNULL_BEGIN

typedef CFTypeRef PrivateDevice;

/**
 Abstract class for device-based discovery.
 */
@interface FBDeviceManager<PublicDevice : id> : NSObject <FBiOSTargetSet>

#pragma mark Initializers

/**
 The Desginated Initializer.

 @param logger the logger to use.
 @return a new FBDeviceManager instance.
 */
- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger;

#pragma mark Public

/**
 The current set of devices
 */
@property (nonatomic, copy, readonly)  NSArray<PublicDevice> *currentDeviceList;

#pragma mark Implemented in Subclasses

/**
 Starts listening for device notifications.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise
 */
- (BOOL)startListeningWithError:(NSError **)error;

/**
 Stops listening for device notifications.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise
 */
- (BOOL)stopListeningWithError:(NSError **)error;

/**
 Construct the public type from the private type

 @param privateDevice the private device
 @param identifier the device identifier.
 @param info optional information about the device.
 @return the public device.
 */
- (PublicDevice)constructPublic:(PrivateDevice)privateDevice identifier:(NSString *)identifier info:(nullable NSDictionary<NSString *, id> *)info;

/**
 Construct the public type from the private type

 @param publicDevice the public device
 @param privateDevice the private device
 @param identifier the device identifier.
 @param info optional information about the device.
 */
+ (void)updatePublicReference:(PublicDevice)publicDevice privateDevice:(PrivateDevice)privateDevice identifier:(NSString *)identifier info:(nullable NSDictionary<NSString *, id> *)info;

/**
 Extract the private type from the public type

 @param publicDevice the public device
 @return the private device.
 */
+ (PrivateDevice)extractPrivateReference:(PublicDevice)publicDevice;

#pragma mark Called in Subclasses

/**
 Call when the device is connected.

 @param privateDevice the device reference.
 @param identifier the device identifier
 @param info optional information about the device.
 */
- (void)deviceConnected:(PrivateDevice)privateDevice identifier:(NSString *)identifier info:(nullable NSDictionary<NSString *, id> *)info;

/**
 Call when the device is disconnected.

 @param privateDevice the device reference.
 @param identifier the device identifier
 */
- (void)deviceDisconnected:(PrivateDevice)privateDevice identifier:(NSString *)identifier;

/**
 The logger to use.
 */
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

/**
 The Storage of Device instances.
 */
@property (nonatomic, strong, readonly) FBDeviceStorage<PublicDevice> *storage;

@end

NS_ASSUME_NONNULL_END

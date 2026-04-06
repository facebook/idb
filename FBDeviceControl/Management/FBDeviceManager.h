/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBAMDefines.h>

@class FBDeviceStorage;

typedef CFTypeRef PrivateDevice;

/**
 Abstract class for device-based discovery.
 */
@interface FBDeviceManager <PublicDevice : id> : NSObject <FBiOSTargetSet>

#pragma mark Initializers

/**
 The Desginated Initializer.

 @param logger the logger to use.
 @return a new FBDeviceManager instance.
 */
- (nonnull instancetype)initWithLogger:(nonnull id<FBControlCoreLogger>)logger;

#pragma mark Public

/**
 The current set of devices
 */
@property (nonnull, nonatomic, readonly, copy) NSArray<PublicDevice> *currentDeviceList;

#pragma mark Implemented in Subclasses

/**
 Starts listening for device notifications.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise
 */
- (BOOL)startListeningWithError:(NSError * _Nullable * _Nullable)error;

/**
 Stops listening for device notifications.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise
 */
- (BOOL)stopListeningWithError:(NSError * _Nullable * _Nullable)error;

/**
 Construct the public type from the private type

 @param privateDevice the private device
 @param identifier the device identifier.
 @param info optional information about the device.
 @return the public device.
 */
- (nonnull PublicDevice)constructPublic:(PrivateDevice _Nonnull)privateDevice identifier:(nonnull NSString *)identifier info:(nullable NSDictionary<NSString *, id> *)info;

/**
 Update the public type with data from the private type

 @param publicDevice the public device
 @param privateDevice the private device
 @param identifier the device identifier.
 @param info optional information about the device.
 */
+ (void)updatePublicReference:(nonnull PublicDevice)publicDevice privateDevice:(PrivateDevice _Nonnull)privateDevice identifier:(nonnull NSString *)identifier info:(nullable NSDictionary<NSString *, id> *)info;

/**
 Extract the private type from the public type

 @param publicDevice the public device
 @return the private device.
 */
+ (PrivateDevice _Nullable)extractPrivateReference:(nonnull PublicDevice)publicDevice;

#pragma mark Called in Subclasses

/**
 Call when the device is connected.

 @param privateDevice the device reference.
 @param identifier the device identifier
 @param info optional information about the device.
 */
- (void)deviceConnected:(PrivateDevice _Nonnull)privateDevice identifier:(nonnull NSString *)identifier info:(nullable NSDictionary<NSString *, id> *)info;

/**
 Call when the device is disconnected.

 @param privateDevice the device reference.
 @param identifier the device identifier
 */
- (void)deviceDisconnected:(PrivateDevice _Nonnull)privateDevice identifier:(nonnull NSString *)identifier;

/**
 The logger to use.
 */
@property (nonnull, nonatomic, readonly, strong) id<FBControlCoreLogger> logger;

/**
 The Storage of Device instances.
 */
@property (nonnull, nonatomic, readonly, strong) FBDeviceStorage *storage;

@end

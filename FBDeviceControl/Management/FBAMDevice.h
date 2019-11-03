/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDeviceType;
@class FBOSVersion;

/**
 An Object Wrapper for AMDevice.
 AMDevice is a Core Foundation Type in the MobileDevice.framework.
 */
@interface FBAMDevice : NSObject

#pragma mark Initializers

/**
 Returns an Array of all the Available Devices.
 */
+ (NSArray<FBAMDevice *> *)allDevices;

#pragma mark Properties

/**
 The Unique Identifier of the Device.
 */
@property (nonatomic, nullable, copy, readonly) NSString *udid;

/**
 The User-Defined name of the Device, e.g. "Ada's iPhone".
 */
@property (nonatomic, nullable, copy, readonly) NSString *deviceName;

/**
 The Product Type. e.g 'iPhone8,1'
 */
@property (nonatomic, nullable, copy, readonly) NSString *productType;

/**
 The Device's 'Model Name'.
 */
@property (nonatomic, nullable, copy, readonly) NSString *modelName;

/**
 The Device's 'Product Version'.
 */
@property (nonatomic, nullable, copy, readonly) NSString *productVersion;

/**
 The Device's 'Build Version'.
 */
@property (nonatomic, nullable, copy, readonly) NSString *buildVersion;

/**
 The FBControlCore Configuration Variant representing the Device.
 */
@property (nonatomic, nullable, copy, readonly) FBDeviceType *deviceConfiguration;

/**
 The FBControlCore Configuration Variant representing the Operating System.
 */
@property (nonatomic, nullable, copy, readonly) FBOSVersion *osConfiguration;

/**
 The Architechture of the Device's CPU.
 */
@property (nonatomic, nullable, copy, readonly) NSString *architecture;

@end

NS_ASSUME_NONNULL_END

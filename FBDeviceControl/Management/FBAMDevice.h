/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
 Sets the Default Log Level and File Path for MobileDevice.framework.
 Must be called before any MobileDevice APIs are called, as these values are read during Framework initialization.
 Logging goes via asl instead of os_log, so logging to a file path may be unpredicatable.

 @param level the Log Level to use.
 @param logFilePath the file path to log to.
 */
+ (void)setDefaultLogLevel:(int)level logFilePath:(NSString *)logFilePath;

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
 The Device's 'System Version'.
 */
@property (nonatomic, nullable, copy, readonly) NSString *systemVersion;

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

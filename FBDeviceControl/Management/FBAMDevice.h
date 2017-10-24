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
 Loads AMDevice symbols required by this class to work properly.
 Should be called before any other call to this class is made.
 */
+ (void)loadFBAMDeviceSymbols;

/**
 Turns on asl debug logs for all AMDevice services
 */
+ (void)enableDebugLogging;

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

#pragma mark Public

/**
 Build a Future from an operation for performing on a device.

 @param block the block to execute for the device.
 @return a Future that resolves with the result of the block.
 */
- (FBFuture *)futureForDeviceOperation:(id(^)(CFTypeRef, NSError **))block;

/**
 Starts test manager daemon service

 @return AMDServiceConnection if the operation succeeds, otherwise NULL.
 */
- (CFTypeRef)startTestManagerServiceWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

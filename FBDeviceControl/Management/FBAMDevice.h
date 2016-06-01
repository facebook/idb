/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An Object Wrapper for AMDevice.
 AMDevice is a Core Foundation Type in the MobileDevice.framework.
 */
@interface FBAMDevice : NSObject

/**
 Returns an Array of all the Available Devices.
 */
+ (NSArray<FBAMDevice *> *)allDevices;

/**
 The Unique Identifier of the Device.
 */
@property (nonatomic, nullable, copy, readonly) NSString *udid;

/**
 The User-Defined name of the Device, e.g. "Ada's iPhone".
 */
@property (nonatomic, nullable, copy, readonly) NSString *deviceName;

/**
 The Device's 'Model Name'.
 */
@property (nonatomic, nullable, copy, readonly) NSString *modelName;

/**
 The Device's 'System Version'.
 */
@property (nonatomic, nullable, copy, readonly) NSString *systemVersion;

@end

NS_ASSUME_NONNULL_END

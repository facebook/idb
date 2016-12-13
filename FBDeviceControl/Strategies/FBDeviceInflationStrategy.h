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

@class FBAMDevice;
@class FBDevice;
@class FBDeviceSet;

/**
 A Strategy for Inflating FBDevice instances.
 Ensures that FBDeviceSet can maintain the same references to FBDevice instances over time.
 The FBAMDevice instances represent the 'Truth' in terms of attached devices.
 The FBDevice instances should reflect this.
 */
@interface FBDeviceInflationStrategy : NSObject

/**
 Creates and returns a new Inflation Strategy.

 @param set the Device Set to insert into.
 @return a new Device Set Strategy Instance.
 */
+ (instancetype)forSet:(FBDeviceSet *)set;

/**
 Creates the Array of Simulators matching the Array of SimDevices passed in.
 Will Create and Remove SimDevice instances so as to make the Simulators and wrapped SimDevices consistent.

 @param amDevices the existing FBAMDevice Instances.
 @param devices the existing FBDevice instances, if any.
 @return an array of FBDevice instances matching the SimDevices.
 */
- (NSArray<FBDevice *> *)inflateFromDevices:(NSArray<FBAMDevice *> *)amDevices existingDevices:(NSArray<FBDevice *> *)devices;

@end

NS_ASSUME_NONNULL_END

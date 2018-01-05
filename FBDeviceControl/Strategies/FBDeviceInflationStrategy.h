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
 Ensures that owners of FBDevice instances have FBDevice instances represent the same devices over time.
 The source of truth for the current available devices is determined by the FBAMDevice array passed in.
 It is up for the caller to construct the appropriate array of FBAMDevices
 */
@interface FBDeviceInflationStrategy : NSObject

#pragma mark Initializers

/**
 Creates and returns a new Inflation Strategy.

 @param set the Device Set to insert into.
 @return a new Device Set Strategy Instance.
 */
+ (instancetype)strategyForSet:(FBDeviceSet *)set;

#pragma mark Public Methods

/**
 Creates the Array of Simulators matching the Array of SimDevices passed in.
 Will Create and Remove SimDevice instances so as to make the Simulators and wrapped SimDevices consistent.

 @param amDevices the existing FB_AMDevice Instances.
 @param devices the existing FBDevice instances, if any.
 @return an array of FBDevice instances matching the SimDevices.
 */
- (NSArray<FBDevice *> *)inflateFromDevices:(NSArray<FBAMDevice *> *)amDevices existingDevices:(NSArray<FBDevice *> *)devices;

@end

NS_ASSUME_NONNULL_END

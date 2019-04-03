/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDeviceSet;
@protocol FBControlCoreLogger;

/**
 A class that represents an iOS Device.
 */
@interface FBDevice : NSObject <FBiOSTarget>

/**
 The Device Set to which the Device Belongs.
 */
@property (nonatomic, weak, readonly) FBDeviceSet *set;

/**
 Device's name
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 Device's model name
 */
@property (nonatomic, copy, readonly) NSString *modelName;

/**
 Device's 'Product Version'
 */
@property (nonatomic, copy, readonly) NSString *productVersion;

/**
 Device's 'Product Version'
 */
@property (nonatomic, copy, readonly) NSString *buildVersion;

/**
 Interpolated NSOperatingSystemVersion.
 */
@property (nonatomic, assign, readonly) NSOperatingSystemVersion operatingSystemVersion;

/**
 Constructs an Operating System Version from a string.

 @param string the string to interpolate.
 @return an NSOperatingSystemVersion for the string.
 */
+ (NSOperatingSystemVersion)operatingSystemVersionFromString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END

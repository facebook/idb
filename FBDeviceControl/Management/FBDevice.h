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
#import <XCTestBootstrap/XCTestBootstrap.h>

@class FBDeviceSet;
@class FBProductBundle;
@class FBTestRunnerConfiguration;
@protocol FBDeviceOperator;
@protocol FBControlCoreLogger;

NS_ASSUME_NONNULL_BEGIN

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

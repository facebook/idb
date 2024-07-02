/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Value object that represents the Configuration of a iPhone, iPad, Watch or TV Simulator.

 Class is designed around maximum convenience for specifying a configuration.
 For example to specify an iPad 2 on iOS 8.2:
 `FBSimulatorConfiguration.iPad2.iOS_8_2`.

 It is also possible to specify configurations based on a NSString.
 This is helpful when creating a device from something specified in an Environment Variable:
 `[FBSimulatorConfiguration.iPhone5 iOS:NSProcessInfo.processInfo.environment[@"TARGET_OS"]]`
 */
@interface FBSimulatorConfiguration : NSObject <NSCopying>

#pragma mark Properties

/**
 The Device Configuration.
 */
@property (nonatomic, strong, readonly) FBDeviceType *device;

/**
 The OS Configuration.
 */
@property (nonatomic, strong, readonly) FBOSVersion *os;

/**
 Returns the Default Configuration.
 The OS Version is derived from the SDK Version.
 */
@property (nonatomic, copy, readonly, class) FBSimulatorConfiguration *defaultConfiguration;

#pragma mark Models

/**
 Returns a new configuration, applying the specified model.
 
 @param model the model to apply
 @return a new configuration
 */
- (instancetype)withDeviceModel:(FBDeviceModel)model;

#pragma mark OS Versions

/**
 Returns a new configuration, applying the specified os name..
 
 @param osName the OS Name.
 @return a new configuration.
 */
- (instancetype)withOSNamed:(FBOSVersionName)osName;

@end

NS_ASSUME_NONNULL_END

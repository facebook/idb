/*
 * Copyright (c) Facebook, Inc. and its affiliates.
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
@interface FBSimulatorConfiguration : NSObject <NSCopying, FBJSONSerializable, FBDebugDescribeable>

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
 The Location to store auxillary files in.
 Auxillary files are stored per-simulator, so will be nested inside directories for each Simulator.
 If no path is provided, a default Auxillary directory inside the Simulator's data directory will be used.
 */
@property (nonatomic, copy, nullable, readonly) NSString *auxillaryDirectory;

/**
 Returns the Default Configuration.
 The OS Version is derived from the SDK Version.
 */
+ (instancetype)defaultConfiguration;

#pragma mark - Devices

/**
 A Configuration with the provided Device Name.
 Will assume a 'Default' Configuration of the provided Device Name if it is unknown to the Framework.
 */
+ (instancetype)withDeviceModel:(FBDeviceModel)model;
- (instancetype)withDeviceModel:(FBDeviceModel)model;

#pragma mark - OS Versions

/**
 A Configuration with the provided OS Name.
 Will assert if the deviceName is not a valid Device Name.
 */
+ (instancetype)withOSNamed:(FBOSVersionName)osName;
- (instancetype)withOSNamed:(FBOSVersionName)osName;

#pragma mark Auxillary Directory

/**
 Updates the Auxillary Directory.
 */
- (instancetype)withAuxillaryDirectory:(NSString *)auxillaryDirectory;

@end

NS_ASSUME_NONNULL_END

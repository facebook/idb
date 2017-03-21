/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBArchitecture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Uses the known values of SimDeviceType ProductFamilyID, to construct an enumeration.
 These mirror the values from -[SimDeviceState productFamilyID].
 */
typedef NS_ENUM(NSUInteger, FBControlCoreProductFamily) {
  FBControlCoreProductFamilyUnknown = 0,
  FBControlCoreProductFamilyiPhone = 1,
  FBControlCoreProductFamilyiPad = 2,
  FBControlCoreProductFamilyAppleTV = 3,
  FBControlCoreProductFamilyAppleWatch = 4,
};

/**
 Device Names Enumeration.
 */
typedef NSString *FBDeviceName NS_STRING_ENUM;

extern FBDeviceName const FBDeviceNameiPhone4s;
extern FBDeviceName const FBDeviceNameiPhone5;
extern FBDeviceName const FBDeviceNameiPhone5s;
extern FBDeviceName const FBDeviceNameiPhone6;
extern FBDeviceName const FBDeviceNameiPhone6Plus;
extern FBDeviceName const FBDeviceNameiPhone6S;
extern FBDeviceName const FBDeviceNameiPhone6SPlus;
extern FBDeviceName const FBDeviceNameiPhoneSE;
extern FBDeviceName const FBDeviceNameiPhone7;
extern FBDeviceName const FBDeviceNameiPhone7Plus;
extern FBDeviceName const FBDeviceNameiPad2;
extern FBDeviceName const FBDeviceNameiPadRetina;
extern FBDeviceName const FBDeviceNameiPadAir;
extern FBDeviceName const FBDeviceNameiPadAir2;
extern FBDeviceName const FBDeviceNameiPadPro;
extern FBDeviceName const FBDeviceNameiPadPro_9_7_Inch;
extern FBDeviceName const FBDeviceNameiPadPro_12_9_Inch;
extern FBDeviceName const FBDeviceNameAppleTV1080p;
extern FBDeviceName const FBDeviceNameAppleWatch38mm;
extern FBDeviceName const FBDeviceNameAppleWatch42mm;
extern FBDeviceName const FBDeviceNameAppleWatchSeries2_38mm;
extern FBDeviceName const FBDeviceNameAppleWatchSeries2_42mm;

/**
 OS Versions Name Enumeration.
 */
typedef NSString *FBOSVersionName NS_STRING_ENUM;

extern FBOSVersionName const FBOSVersionNameiOS_7_1;
extern FBOSVersionName const FBOSVersionNameiOS_8_0;
extern FBOSVersionName const FBOSVersionNameiOS_8_1;
extern FBOSVersionName const FBOSVersionNameiOS_8_2;
extern FBOSVersionName const FBOSVersionNameiOS_8_3;
extern FBOSVersionName const FBOSVersionNameiOS_8_4;
extern FBOSVersionName const FBOSVersionNameiOS_9_0;
extern FBOSVersionName const FBOSVersionNameiOS_9_1;
extern FBOSVersionName const FBOSVersionNameiOS_9_2;
extern FBOSVersionName const FBOSVersionNameiOS_9_3;
extern FBOSVersionName const FBOSVersionNameiOS_9_3_1;
extern FBOSVersionName const FBOSVersionNameiOS_9_3_2;
extern FBOSVersionName const FBOSVersionNameiOS_10_0;
extern FBOSVersionName const FBOSVersionNameiOS_10_1;
extern FBOSVersionName const FBOSVersionNameiOS_10_2;
extern FBOSVersionName const FBOSVersionNameiOS_10_3;
extern FBOSVersionName const FBOSVersionNametvOS_9_0;
extern FBOSVersionName const FBOSVersionNametvOS_9_1;
extern FBOSVersionName const FBOSVersionNametvOS_9_2;
extern FBOSVersionName const FBOSVersionNametvOS_10_0;
extern FBOSVersionName const FBOSVersionNametvOS_10_1;
extern FBOSVersionName const FBOSVersionNametvOS_10_2;
extern FBOSVersionName const FBOSVersionNamewatchOS_2_0;
extern FBOSVersionName const FBOSVersionNamewatchOS_2_1;
extern FBOSVersionName const FBOSVersionNamewatchOS_2_2;
extern FBOSVersionName const FBOSVersionNamewatchOS_3_0;
extern FBOSVersionName const FBOSVersionNamewatchOS_3_1;
extern FBOSVersionName const FBOSVersionNamewatchOS_3_2;

@interface FBControlCoreConfigurationVariant_Base : NSObject <NSCoding, NSCopying>
@end

#pragma mark Devices

@interface FBDeviceType : NSObject <NSCopying>

/**
 The Device Name of the Device.
 */
@property (nonatomic, copy, readonly) FBDeviceName deviceName;

/**
 The String Representations of the Product Types.
 */
@property (nonatomic, copy, readonly) NSSet<NSString *> *productTypes;

/**
 The native Device Architecture.
 */
@property (nonatomic, copy, readonly) FBArchitecture deviceArchitecture;

/**
 The Native Simulator Arhitecture.
 */
@property (nonatomic, copy, readonly) FBArchitecture simulatorArchitecture;

/**
 The Supported Product Family.
 */
@property (nonatomic, assign, readonly) FBControlCoreProductFamily family;

@end

#pragma mark OS Versions

@interface FBOSVersion : NSObject <NSCopying>

/**
 The Version name of the OS.
 */
@property (nonatomic, copy, readonly) FBOSVersionName name;

/**
 A Decimal Number Represnting the Version Number.
 */
@property (nonatomic, copy, readonly) NSDecimalNumber *number;

/**
 The Supported Families of the OS Version.
 */
@property (nonatomic, copy, readonly) NSSet<NSNumber *> *families;

/**
 A Generic OS with the Given Name.
 */
+ (instancetype)genericWithName:(NSString *)name;

@end

/**
 Mappings of Variants.
 */
@interface FBControlCoreConfigurationVariants : NSObject

/**
 Maps Device Names to Devices.
 */
@property (class, nonatomic, copy, readonly) NSDictionary<FBDeviceName, FBDeviceType *> *nameToDevice;

/**
 Maps Device 'ProductType' to Device Variants.
 */
@property (class, nonatomic, copy, readonly) NSDictionary<NSString *, FBDeviceType *> *productTypeToDevice;

/**
 OS Version names to OS Versions.
 */
@property (class, nonatomic, copy, readonly) NSDictionary<FBOSVersionName, FBOSVersion *> *nameToOSVersion;

/**
 Maps the architechture of the target to the compatible architechtures for binaries on the target.
 */
@property (class, nonatomic, copy, readonly) NSDictionary<FBArchitecture, NSSet<FBArchitecture> *> *baseArchToCompatibleArch;

@end

NS_ASSUME_NONNULL_END

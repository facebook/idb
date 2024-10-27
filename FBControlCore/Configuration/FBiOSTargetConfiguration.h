/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
  FBControlCoreProductFamilyMac = 5,
};

/**
 Device Names Enumeration.
 */
typedef NSString *FBDeviceModel NS_STRING_ENUM;

extern FBDeviceModel const FBDeviceModeliPhone4s;
extern FBDeviceModel const FBDeviceModeliPhone5;
extern FBDeviceModel const FBDeviceModeliPhone5c;
extern FBDeviceModel const FBDeviceModeliPhone5s;
extern FBDeviceModel const FBDeviceModeliPhone6;
extern FBDeviceModel const FBDeviceModeliPhone6Plus;
extern FBDeviceModel const FBDeviceModeliPhone6S;
extern FBDeviceModel const FBDeviceModeliPhone6SPlus;
extern FBDeviceModel const FBDeviceModeliPhoneSE_1stGeneration;
extern FBDeviceModel const FBDeviceModeliPhoneSE_2ndGeneration;
extern FBDeviceModel const FBDeviceModeliPhone7;
extern FBDeviceModel const FBDeviceModeliPhone7Plus;
extern FBDeviceModel const FBDeviceModeliPhone8;
extern FBDeviceModel const FBDeviceModeliPhone8Plus;
extern FBDeviceModel const FBDeviceModeliPhoneX;
extern FBDeviceModel const FBDeviceModeliPhoneXs;
extern FBDeviceModel const FBDeviceModeliPhoneXsMax;
extern FBDeviceModel const FBDeviceModeliPhoneXr;
extern FBDeviceModel const FBDeviceModeliPhone11;
extern FBDeviceModel const FBDeviceModeliPhone11Pro;
extern FBDeviceModel const FBDeviceModeliPhone11ProMax;
extern FBDeviceModel const FBDeviceModeliPhone12mini;
extern FBDeviceModel const FBDeviceModeliPhone12;
extern FBDeviceModel const FBDeviceModeliPhone12Pro;
extern FBDeviceModel const FBDeviceModeliPhone12ProMax;
extern FBDeviceModel const FBDeviceModeliPhone13mini;
extern FBDeviceModel const FBDeviceModeliPhone13;
extern FBDeviceModel const FBDeviceModeliPhone13Pro;
extern FBDeviceModel const FBDeviceModeliPhone13ProMax;
extern FBDeviceModel const FBDeviceModeliPhone14;
extern FBDeviceModel const FBDeviceModeliPhone14Plus;
extern FBDeviceModel const FBDeviceModeliPhone14Pro;
extern FBDeviceModel const FBDeviceModeliPhone14ProMax;
extern FBDeviceModel const FBDeviceModeliPhone15;
extern FBDeviceModel const FBDeviceModeliPhone15Plus;
extern FBDeviceModel const FBDeviceModeliPhone15Pro;
extern FBDeviceModel const FBDeviceModeliPhone15ProMax;
extern FBDeviceModel const FBDeviceModeliPhone16;
extern FBDeviceModel const FBDeviceModeliPhone16Plus;
extern FBDeviceModel const FBDeviceModeliPhone16Pro;
extern FBDeviceModel const FBDeviceModeliPhone16ProMax;
extern FBDeviceModel const FBDeviceModeliPodTouch_7thGeneration;
extern FBDeviceModel const FBDeviceModeliPad2;
extern FBDeviceModel const FBDeviceModeliPad_6thGeneration;
extern FBDeviceModel const FBDeviceModeliPad_7thGeneration;
extern FBDeviceModel const FBDeviceModeliPad_8thGeneration;
extern FBDeviceModel const FBDeviceModeliPadRetina;
extern FBDeviceModel const FBDeviceModeliPadAir;
extern FBDeviceModel const FBDeviceModeliPadAir2;
extern FBDeviceModel const FBDeviceModeliPadAir_3rdGeneration;
extern FBDeviceModel const FBDeviceModeliPadAir_4thGeneration;
extern FBDeviceModel const FBDeviceModeliPadPro;
extern FBDeviceModel const FBDeviceModeliPadPro_9_7_Inch;
extern FBDeviceModel const FBDeviceModeliPadPro_12_9_Inch;
extern FBDeviceModel const FBDeviceModeliPadPro_9_7_Inch_2ndGeneration;
extern FBDeviceModel const FBDeviceModeliPadPro_12_9_Inch_2ndGeneration;
extern FBDeviceModel const FBDeviceModeliPadPro_12_9_Inch_3rdGeneration;
extern FBDeviceModel const FBDeviceModeliPadPro_12_9_Inch_4thGeneration;
extern FBDeviceModel const FBDeviceModeliPadPro_10_5_Inch;
extern FBDeviceModel const FBDeviceModeliPadPro_11_Inch_1stGeneration;
extern FBDeviceModel const FBDeviceModeliPadPro_12_9nch_1stGeneration;
extern FBDeviceModel const FBDeviceModeliPadPro_11_Inch_2ndGeneration;
extern FBDeviceModel const FBDeviceModeliPadMini_2;
extern FBDeviceModel const FBDeviceModeliPadMini_3;
extern FBDeviceModel const FBDeviceModeliPadMini_4;
extern FBDeviceModel const FBDeviceModeliPadMini_5;
extern FBDeviceModel const FBDeviceModelAppleTV;
extern FBDeviceModel const FBDeviceModelAppleTV4K;
extern FBDeviceModel const FBDeviceModelAppleTV4KAt1080p;
extern FBDeviceModel const FBDeviceModelAppleWatch38mm;
extern FBDeviceModel const FBDeviceModelAppleWatch42mm;
extern FBDeviceModel const FBDeviceModelAppleWatchSE_40mm;
extern FBDeviceModel const FBDeviceModelAppleWatchSE_44mm;
extern FBDeviceModel const FBDeviceModelAppleWatchSeries2_38mm;
extern FBDeviceModel const FBDeviceModelAppleWatchSeries2_42mm;
extern FBDeviceModel const FBDeviceModelAppleWatchSeries3_38mm;
extern FBDeviceModel const FBDeviceModelAppleWatchSeries3_42mm;
extern FBDeviceModel const FBDeviceModelAppleWatchSeries4_40mm;
extern FBDeviceModel const FBDeviceModelAppleWatchSeries4_44mm;
extern FBDeviceModel const FBDeviceModelAppleWatchSeries5_40mm;
extern FBDeviceModel const FBDeviceModelAppleWatchSeries5_44mm;
extern FBDeviceModel const FBDeviceModelAppleWatchSeries6_40mm;
extern FBDeviceModel const FBDeviceModelAppleWatchSeries6_44mm;

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
extern FBOSVersionName const FBOSVersionNameiOS_11_0;
extern FBOSVersionName const FBOSVersionNameiOS_11_1;
extern FBOSVersionName const FBOSVersionNameiOS_11_2;
extern FBOSVersionName const FBOSVersionNameiOS_11_3;
extern FBOSVersionName const FBOSVersionNameiOS_11_4;
extern FBOSVersionName const FBOSVersionNameiOS_12_0;
extern FBOSVersionName const FBOSVersionNameiOS_12_1;
extern FBOSVersionName const FBOSVersionNameiOS_12_2;
extern FBOSVersionName const FBOSVersionNameiOS_12_4;
extern FBOSVersionName const FBOSVersionNameiOS_13_0;
extern FBOSVersionName const FBOSVersionNameiOS_13_1;
extern FBOSVersionName const FBOSVersionNameiOS_13_2;
extern FBOSVersionName const FBOSVersionNameiOS_13_3;
extern FBOSVersionName const FBOSVersionNameiOS_13_4;
extern FBOSVersionName const FBOSVersionNameiOS_13_5;
extern FBOSVersionName const FBOSVersionNameiOS_14_0;
extern FBOSVersionName const FBOSVersionNameiOS_14_1;
extern FBOSVersionName const FBOSVersionNameiOS_14_2;
extern FBOSVersionName const FBOSVersionNametvOS_9_0;
extern FBOSVersionName const FBOSVersionNametvOS_9_1;
extern FBOSVersionName const FBOSVersionNametvOS_9_2;
extern FBOSVersionName const FBOSVersionNametvOS_10_0;
extern FBOSVersionName const FBOSVersionNametvOS_10_1;
extern FBOSVersionName const FBOSVersionNametvOS_10_2;
extern FBOSVersionName const FBOSVersionNametvOS_11_0;
extern FBOSVersionName const FBOSVersionNametvOS_11_1;
extern FBOSVersionName const FBOSVersionNametvOS_11_2;
extern FBOSVersionName const FBOSVersionNametvOS_11_3;
extern FBOSVersionName const FBOSVersionNametvOS_11_4;
extern FBOSVersionName const FBOSVersionNametvOS_12_0;
extern FBOSVersionName const FBOSVersionNametvOS_12_1;
extern FBOSVersionName const FBOSVersionNametvOS_12_2;
extern FBOSVersionName const FBOSVersionNametvOS_12_4;
extern FBOSVersionName const FBOSVersionNametvOS_13_0;
extern FBOSVersionName const FBOSVersionNametvOS_13_2;
extern FBOSVersionName const FBOSVersionNametvOS_13_3;
extern FBOSVersionName const FBOSVersionNametvOS_13_4;
extern FBOSVersionName const FBOSVersionNametvOS_14_0;
extern FBOSVersionName const FBOSVersionNametvOS_14_1;
extern FBOSVersionName const FBOSVersionNametvOS_14_2;
extern FBOSVersionName const FBOSVersionNamewatchOS_2_0;
extern FBOSVersionName const FBOSVersionNamewatchOS_2_1;
extern FBOSVersionName const FBOSVersionNamewatchOS_2_2;
extern FBOSVersionName const FBOSVersionNamewatchOS_3_0;
extern FBOSVersionName const FBOSVersionNamewatchOS_3_1;
extern FBOSVersionName const FBOSVersionNamewatchOS_3_2;
extern FBOSVersionName const FBOSVersionNamewatchOS_4_0;
extern FBOSVersionName const FBOSVersionNamewatchOS_4_1;
extern FBOSVersionName const FBOSVersionNamewatchOS_4_2;
extern FBOSVersionName const FBOSVersionNamewatchOS_5_0;
extern FBOSVersionName const FBOSVersionNamewatchOS_5_1;
extern FBOSVersionName const FBOSVersionNamewatchOS_5_2;
extern FBOSVersionName const FBOSVersionNamewatchOS_5_3;
extern FBOSVersionName const FBOSVersionNamewatchOS_6_0;
extern FBOSVersionName const FBOSVersionNamewatchOS_6_1;
extern FBOSVersionName const FBOSVersionNamewatchOS_6_2;
extern FBOSVersionName const FBOSVersionNamewatchOS_7_0;
extern FBOSVersionName const FBOSVersionNamewatchOS_7_1;
extern FBOSVersionName const FBOSVersionNamemac;

#pragma mark Screen

/**
 Information about the Screen.
 */
@interface FBiOSTargetScreenInfo : NSObject <NSCopying>

/**
 The Width of the Screen in Pixels.
 */
@property (nonatomic, assign, readonly) NSUInteger widthPixels;

/**
 The Height of the Screen in Pixels.
 */
@property (nonatomic, assign, readonly) NSUInteger heightPixels;

/**
 The Scale of the Screen.
 */
@property (nonatomic, assign, readonly) float scale;

/**
 The Designated Initializer.
 */
- (instancetype)initWithWidthPixels:(NSUInteger)widthPixels heightPixels:(NSUInteger)heightPixels scale:(float)scale;

@end

#pragma mark Devices

@interface FBDeviceType : NSObject <NSCopying>

/**
 The Device Name of the Device.
 */
@property (nonatomic, copy, readonly) FBDeviceModel model;

/**
 The String Representations of the Product Types.
 */
@property (nonatomic, copy, readonly) NSSet<NSString *> *productTypes;

/**
 The native Device Architecture.
 */
@property (nonatomic, copy, readonly) FBArchitecture deviceArchitecture;

/**
 The Supported Product Family.
 */
@property (nonatomic, assign, readonly) FBControlCoreProductFamily family;

/**
 A Generic Device with the Given Name.
 */
+ (instancetype)genericWithName:(NSString *)name;

@end

#pragma mark OS Versions

@interface FBOSVersion : NSObject <NSCopying>

/**
 A string representation of the OS Version.
 */
@property (nonatomic, copy, readonly) FBOSVersionName name;

/**
 A String representation of the numeric part of the OS Version.
 */
@property (nonatomic, copy, readonly) NSString *versionString;

/**
 An NSDecimalNumber representation of the numeric part of the OS Version.
 */
@property (nonatomic, copy, readonly) NSDecimalNumber *number;

/**
 An NSOperatingSystemVersion representation of the numeric part of the OS Version.
 */
@property (nonatomic, assign, readonly) NSOperatingSystemVersion version;

/**
 The Supported Families of the OS Version.
 */
@property (nonatomic, copy, readonly) NSSet<NSNumber *> *families;

/**
 A Generic OS with the Given Name.
 */
+ (instancetype)genericWithName:(NSString *)name;

/**
 Construct an NSOperatingSystemVersion from a string.

 @param name the name to process.
 @return a new NSOperatingSystemVersion
 */
+ (NSOperatingSystemVersion)operatingSystemVersionFromName:(NSString *)name;

@end

/**
 Mappings of Variants.
 */
@interface FBiOSTargetConfiguration : NSObject

/**
 Maps Device Names to Devices.
 */
@property (class, nonatomic, copy, readonly) NSDictionary<FBDeviceModel, FBDeviceType *> *nameToDevice;

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
+ (NSSet<FBArchitecture> *)baseArchsToCompatibleArch:(NSArray<FBArchitecture>*)architectures;

@end

NS_ASSUME_NONNULL_END

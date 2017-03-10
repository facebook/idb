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

#pragma mark Families

@protocol FBControlCoreConfiguration_Family <NSObject>

@property (nonatomic, assign, readonly) FBControlCoreProductFamily productFamilyID;

@end

@interface FBControlCoreConfiguration_Family_iPhone : FBControlCoreConfigurationVariant_Base <FBControlCoreConfiguration_Family>

@end

@interface FBControlCoreConfiguration_Family_iPad : FBControlCoreConfigurationVariant_Base <FBControlCoreConfiguration_Family>

@end

@interface FBControlCoreConfiguration_Family_Watch : FBControlCoreConfigurationVariant_Base <FBControlCoreConfiguration_Family>

@end

@interface FBControlCoreConfiguration_Family_TV : FBControlCoreConfigurationVariant_Base <FBControlCoreConfiguration_Family>

@end

#pragma mark Devices

@protocol FBControlCoreConfiguration_Device <NSObject>

@property (nonatomic, copy, readonly) FBDeviceName deviceName;
@property (nonatomic, copy, readonly) NSSet<NSString *> *productTypes;
@property (nonatomic, copy, readonly) FBArchitecture deviceArchitecture;
@property (nonatomic, copy, readonly) FBArchitecture simulatorArchitecture;
@property (nonatomic, strong, readonly) id<FBControlCoreConfiguration_Family> family;

@end

@interface FBControlCoreConfiguration_Device_iPhone_Base : FBControlCoreConfigurationVariant_Base <FBControlCoreConfiguration_Device>
@end

@interface FBControlCoreConfiguration_Device_iPhone4s : FBControlCoreConfiguration_Device_iPhone_Base
@end

@interface FBControlCoreConfiguration_Device_iPhone5 : FBControlCoreConfiguration_Device_iPhone_Base
@end

@interface FBControlCoreConfiguration_Device_iPhone5s : FBControlCoreConfiguration_Device_iPhone_Base
@end

@interface FBControlCoreConfiguration_Device_iPhone6 : FBControlCoreConfiguration_Device_iPhone_Base
@end

@interface FBControlCoreConfiguration_Device_iPhone6Plus : FBControlCoreConfiguration_Device_iPhone_Base
@end

@interface FBControlCoreConfiguration_Device_iPhone6S : FBControlCoreConfiguration_Device_iPhone_Base
@end

@interface FBControlCoreConfiguration_Device_iPhone6SPlus : FBControlCoreConfiguration_Device_iPhone_Base
@end

@interface FBControlCoreConfiguration_Device_iPhoneSE : FBControlCoreConfiguration_Device_iPhone_Base
@end

@interface FBControlCoreConfiguration_Device_iPhone7 : FBControlCoreConfiguration_Device_iPhone_Base
@end

@interface FBControlCoreConfiguration_Device_iPhone7Plus : FBControlCoreConfiguration_Device_iPhone_Base
@end

@interface FBControlCoreConfiguration_Device_iPad_Base : FBControlCoreConfigurationVariant_Base <FBControlCoreConfiguration_Device>
@end

@interface FBControlCoreConfiguration_Device_iPad2 : FBControlCoreConfiguration_Device_iPad_Base
@end

@interface FBControlCoreConfiguration_Device_iPadRetina : FBControlCoreConfiguration_Device_iPad_Base
@end

@interface FBControlCoreConfiguration_Device_iPadAir : FBControlCoreConfiguration_Device_iPad_Base
@end

@interface FBControlCoreConfiguration_Device_iPadAir2 : FBControlCoreConfiguration_Device_iPad_Base
@end

@interface FBControlCoreConfiguration_Device_iPadPro : FBControlCoreConfiguration_Device_iPad_Base
@end

@interface FBControlCoreConfiguration_Device_iPadPro_9_7_Inch : FBControlCoreConfiguration_Device_iPad_Base
@end

@interface FBControlCoreConfiguration_Device_iPadPro_12_9_Inch : FBControlCoreConfiguration_Device_iPad_Base
@end

@interface FBControlCoreConfiguration_Device_tvOS_Base : FBControlCoreConfigurationVariant_Base <FBControlCoreConfiguration_Device>
@end

@interface FBControlCoreConfiguration_Device_AppleTV1080p : FBControlCoreConfiguration_Device_tvOS_Base
@end

@interface FBControlCoreConfiguration_Device_watchOS_Base : FBControlCoreConfigurationVariant_Base <FBControlCoreConfiguration_Device>
@end

@interface FBControlCoreConfiguration_Device_AppleWatch38mm : FBControlCoreConfiguration_Device_watchOS_Base
@end

@interface FBControlCoreConfiguration_Device_AppleWatch42mm : FBControlCoreConfiguration_Device_watchOS_Base
@end

@interface FBControlCoreConfiguration_Device_AppleWatchSeries2_38mm : FBControlCoreConfiguration_Device_watchOS_Base
@end

@interface FBControlCoreConfiguration_Device_AppleWatchSeries2_42mm : FBControlCoreConfiguration_Device_watchOS_Base
@end

#pragma mark OS Versions

@protocol FBControlCoreConfiguration_OS <NSObject>

@property (nonatomic, copy, readonly) FBOSVersionName name;
@property (nonatomic, copy, readonly) NSDecimalNumber *versionNumber;
@property (nonatomic, copy, readonly) NSSet *families;

@end

@interface FBControlCoreConfiguration_OS_Base : FBControlCoreConfigurationVariant_Base <FBControlCoreConfiguration_OS>
@end

@interface FBControlCoreConfiguration_iOS_Base : FBControlCoreConfiguration_OS_Base
@end

@interface FBControlCoreConfiguration_iOS_7_1 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_8_0 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_8_1 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_8_2 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_8_3 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_8_4 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_9_0 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_9_1 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_9_2 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_9_3 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_9_3_1 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_9_3_2 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_10_0 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_10_1 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_10_2 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_10_2_1 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_iOS_10_3 : FBControlCoreConfiguration_iOS_Base
@end

@interface FBControlCoreConfiguration_tvOS_Base : FBControlCoreConfiguration_OS_Base
@end

@interface FBControlCoreConfiguration_tvOS_9_0 : FBControlCoreConfiguration_tvOS_Base
@end

@interface FBControlCoreConfiguration_tvOS_9_1 : FBControlCoreConfiguration_tvOS_Base
@end

@interface FBControlCoreConfiguration_tvOS_9_2 : FBControlCoreConfiguration_tvOS_Base
@end

@interface FBControlCoreConfiguration_tvOS_10_0 : FBControlCoreConfiguration_tvOS_Base
@end

@interface FBControlCoreConfiguration_tvOS_10_1 : FBControlCoreConfiguration_tvOS_Base
@end

@interface FBControlCoreConfiguration_tvOS_10_2 : FBControlCoreConfiguration_tvOS_Base
@end

@interface FBControlCoreConfiguration_watchOS_Base : FBControlCoreConfiguration_OS_Base
@end

@interface FBControlCoreConfiguration_watchOS_2_0 : FBControlCoreConfiguration_watchOS_Base
@end

@interface FBControlCoreConfiguration_watchOS_2_1 : FBControlCoreConfiguration_watchOS_Base
@end

@interface FBControlCoreConfiguration_watchOS_2_2 : FBControlCoreConfiguration_watchOS_Base
@end

@interface FBControlCoreConfiguration_watchOS_3_0 : FBControlCoreConfiguration_watchOS_Base
@end

@interface FBControlCoreConfiguration_watchOS_3_1 : FBControlCoreConfiguration_watchOS_Base
@end

@interface FBControlCoreConfiguration_watchOS_3_2 : FBControlCoreConfiguration_watchOS_Base
@end

@interface FBControlCoreConfiguration_OS_Generic : FBControlCoreConfiguration_OS_Base
- (id)initWithOSName:(NSString *)osName;
@end

/**
 Mappings of Variants.
 */
@interface FBControlCoreConfigurationVariants : NSObject

/**
 Maps Device Names to Devices.
 */
@property (class, nonatomic, copy, readonly) NSDictionary<FBDeviceName, id<FBControlCoreConfiguration_Device>> *nameToDevice;

/**
 Maps Device 'ProductType' to Device Variants.
 */
@property (class, nonatomic, copy, readonly) NSDictionary<NSString *, id<FBControlCoreConfiguration_Device>> *productTypeToDevice;

/**
 OS Version names to OS Versions.
 */
@property (class, nonatomic, copy, readonly) NSDictionary<FBOSVersionName, id<FBControlCoreConfiguration_OS>> *nameToOSVersion;

/**
 Maps the architechture of the target to the compatible architechtures for binaries on the target.
 */
@property (class, nonatomic, copy, readonly) NSDictionary<FBArchitecture, NSSet<FBArchitecture> *> *baseArchToCompatibleArch;

@end

NS_ASSUME_NONNULL_END

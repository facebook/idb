/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetConfiguration.h"

#import "FBArchitecture.h"

FBDeviceModel const FBDeviceModeliPhone4s = @"iPhone 4s";
FBDeviceModel const FBDeviceModeliPhone5 = @"iPhone 5";
FBDeviceModel const FBDeviceModeliPhone5c = @"iPhone 5c";
FBDeviceModel const FBDeviceModeliPhone5s = @"iPhone 5s";
FBDeviceModel const FBDeviceModeliPhone6 = @"iPhone 6";
FBDeviceModel const FBDeviceModeliPhone6Plus = @"iPhone 6 Plus";
FBDeviceModel const FBDeviceModeliPhone6S = @"iPhone 6s";
FBDeviceModel const FBDeviceModeliPhone6SPlus = @"iPhone 6s Plus";
FBDeviceModel const FBDeviceModeliPhoneSE_1stGeneration = @"iPhone SE (1st generation)";
FBDeviceModel const FBDeviceModeliPhoneSE_2ndGeneration = @"iPhone SE (2nd generation)";
FBDeviceModel const FBDeviceModeliPhone7 = @"iPhone 7";
FBDeviceModel const FBDeviceModeliPhone7Plus = @"iPhone 7 Plus";
FBDeviceModel const FBDeviceModeliPhone8 = @"iPhone 8";
FBDeviceModel const FBDeviceModeliPhone8Plus = @"iPhone 8 Plus";
FBDeviceModel const FBDeviceModeliPhoneX = @"iPhone X";
FBDeviceModel const FBDeviceModeliPhoneXs = @"iPhone Xs";
FBDeviceModel const FBDeviceModeliPhoneXsMax = @"iPhone Xs Max";
FBDeviceModel const FBDeviceModeliPhoneXr = @"iPhone Xʀ";
FBDeviceModel const FBDeviceModeliPhone11 = @"iPhone 11";
FBDeviceModel const FBDeviceModeliPhone11Pro = @"iPhone 11 Pro";
FBDeviceModel const FBDeviceModeliPhone11ProMax = @"iPhone 11 Pro Max";
FBDeviceModel const FBDeviceModeliPhone12mini = @"iPhone 12 mini";
FBDeviceModel const FBDeviceModeliPhone12 = @"iPhone 12";
FBDeviceModel const FBDeviceModeliPhone12Pro = @"iPhone 12 Pro";
FBDeviceModel const FBDeviceModeliPhone12ProMax = @"iPhone 12 Pro Max";
FBDeviceModel const FBDeviceModeliPhone13mini = @"iPhone 13 mini";
FBDeviceModel const FBDeviceModeliPhone13 = @"iPhone 13";
FBDeviceModel const FBDeviceModeliPhone13Pro = @"iPhone 13 Pro";
FBDeviceModel const FBDeviceModeliPhone13ProMax = @"iPhone 13 Pro Max";
FBDeviceModel const FBDeviceModeliPhone14 = @"iPhone 14";
FBDeviceModel const FBDeviceModeliPhone14Plus = @"iPhone 14 Plus";
FBDeviceModel const FBDeviceModeliPhone14Pro = @"iPhone 14 Pro";
FBDeviceModel const FBDeviceModeliPhone14ProMax = @"iPhone 14 Pro Max";
FBDeviceModel const FBDeviceModeliPhone15 = @"iPhone 15";
FBDeviceModel const FBDeviceModeliPhone15Plus = @"iPhone 15 Plus";
FBDeviceModel const FBDeviceModeliPhone15Pro = @"iPhone 15 Pro";
FBDeviceModel const FBDeviceModeliPhone15ProMax = @"iPhone 15 Pro Max";
FBDeviceModel const FBDeviceModeliPodTouch_7thGeneration = @"iPod touch (7th generation)";
FBDeviceModel const FBDeviceModeliPad2 = @"iPad 2";
FBDeviceModel const FBDeviceModeliPadRetina = @"iPad Retina";
FBDeviceModel const FBDeviceModeliPadAir = @"iPad Air";
FBDeviceModel const FBDeviceModeliPadAir2 = @"iPad Air 2";
FBDeviceModel const FBDeviceModeliPadAir_3rdGeneration = @"iPad Air (3rd generation)";
FBDeviceModel const FBDeviceModeliPadAir_4thGeneration = @"iPad Air (4th generation)";
FBDeviceModel const FBDeviceModeliPadPro = @"iPad Pro";
FBDeviceModel const FBDeviceModeliPadPro_9_7_Inch = @"iPad Pro (9.7-inch)";
FBDeviceModel const FBDeviceModeliPadPro_12_9_Inch = @"iPad Pro (12.9-inch)";
FBDeviceModel const FBDeviceModeliPad_5thGeneration = @"iPad (5th generation)";
FBDeviceModel const FBDeviceModeliPadPro_9_7_Inch_2ndGeneration = @"iPad Pro (9.7-inch) (2nd generation)";
FBDeviceModel const FBDeviceModeliPadPro_12_9_Inch_2ndGeneration = @"iPad Pro (12.9-inch) (2nd generation)";
FBDeviceModel const FBDeviceModeliPadPro_10_5_Inch = @"iPad Pro (10.5-inch)";
FBDeviceModel const FBDeviceModeliPad_6thGeneration = @"iPad (6th generation)";
FBDeviceModel const FBDeviceModeliPad_7thGeneration = @"iPad (7th generation)";
FBDeviceModel const FBDeviceModeliPad_8thGeneration = @"iPad (8th generation)";
FBDeviceModel const FBDeviceModeliPadPro_12_9_Inch_3rdGeneration = @"iPad Pro (12.9-inch) (3rd generation)";
FBDeviceModel const FBDeviceModeliPadPro_12_9_Inch_4thGeneration = @"iPad Pro (12.9-inch) (4th generation)";
FBDeviceModel const FBDeviceModeliPadPro_11_Inch_1stGeneration = @"iPad Pro (11-inch) (1st generation)";
FBDeviceModel const FBDeviceModeliPadPro_12_9nch_1stGeneration = @"iPad Pro (12.9-inch) (1st generation)";
FBDeviceModel const FBDeviceModeliPadPro_12_9nch_5thGeneration = @"iPad Pro (12.9-inch) (5th generation)";
FBDeviceModel const FBDeviceModeliPadPro_11_Inch_2ndGeneration = @"iPad Pro (11-inch) (2nd generation)";
FBDeviceModel const FBDeviceModeliPadPro_11_Inch_3ndGeneration = @"iPad Pro (11-inch) (3rd generation)";
FBDeviceModel const FBDeviceModeliPadMini_2 = @"iPad mini 2";
FBDeviceModel const FBDeviceModeliPadMini_3 = @"iPad mini 3";
FBDeviceModel const FBDeviceModeliPadMini_4 = @"iPad mini 4";
FBDeviceModel const FBDeviceModeliPadMini_5 = @"iPad mini (5th generation)";
FBDeviceModel const FBDeviceModelAppleTV = @"Apple TV";
FBDeviceModel const FBDeviceModelAppleTV4K = @"Apple TV 4K";
FBDeviceModel const FBDeviceModelAppleTV4KAt1080p = @"Apple TV 4K (at 1080p)";
FBDeviceModel const FBDeviceModelAppleTV4K_2ndGeneration = @"Apple TV 4K (2nd generation)";
FBDeviceModel const FBDeviceModelAppleTV4KAt1080p_2ndGeneration = @"Apple TV 4K (at 1080p) (2nd generation)";
FBDeviceModel const FBDeviceModelAppleWatch38mm = @"Apple Watch - 38mm";
FBDeviceModel const FBDeviceModelAppleWatch42mm = @"Apple Watch - 42mm";
FBDeviceModel const FBDeviceModelAppleWatchSE_40mm = @"Apple Watch SE - 40mm";
FBDeviceModel const FBDeviceModelAppleWatchSE_44mm = @"Apple Watch SE - 44mm";
FBDeviceModel const FBDeviceModelAppleWatchSeries2_38mm = @"Apple Watch Series 2 - 38mm";
FBDeviceModel const FBDeviceModelAppleWatchSeries2_42mm = @"Apple Watch Series 2 - 42mm";
FBDeviceModel const FBDeviceModelAppleWatchSeries3_38mm = @"Apple Watch Series 3 - 38mm";
FBDeviceModel const FBDeviceModelAppleWatchSeries3_42mm = @"Apple Watch Series 3 - 42mm";
FBDeviceModel const FBDeviceModelAppleWatchSeries4_40mm = @"Apple Watch Series 4 - 40mm";
FBDeviceModel const FBDeviceModelAppleWatchSeries4_44mm = @"Apple Watch Series 4 - 44mm";
FBDeviceModel const FBDeviceModelAppleWatchSeries5_40mm = @"Apple Watch Series 5 - 40mm";
FBDeviceModel const FBDeviceModelAppleWatchSeries5_44mm = @"Apple Watch Series 5 - 44mm";
FBDeviceModel const FBDeviceModelAppleWatchSeries6_40mm = @"Apple Watch Series 6 - 40mm";
FBDeviceModel const FBDeviceModelAppleWatchSeries6_44mm = @"Apple Watch Series 6 - 44mm";

FBOSVersionName const FBOSVersionNameiOS_7_1 = @"iOS 7.1";
FBOSVersionName const FBOSVersionNameiOS_8_0 = @"iOS 8.0";
FBOSVersionName const FBOSVersionNameiOS_8_1 = @"iOS 8.1";
FBOSVersionName const FBOSVersionNameiOS_8_2 = @"iOS 8.2";
FBOSVersionName const FBOSVersionNameiOS_8_3 = @"iOS 8.3";
FBOSVersionName const FBOSVersionNameiOS_8_4 = @"iOS 8.4";
FBOSVersionName const FBOSVersionNameiOS_9_0 = @"iOS 9.0";
FBOSVersionName const FBOSVersionNameiOS_9_1 = @"iOS 9.1";
FBOSVersionName const FBOSVersionNameiOS_9_2 = @"iOS 9.2";
FBOSVersionName const FBOSVersionNameiOS_9_3 = @"iOS 9.3";
FBOSVersionName const FBOSVersionNameiOS_9_3_1 = @"iOS 9.3.1";
FBOSVersionName const FBOSVersionNameiOS_9_3_2 = @"iOS 9.3.2";
FBOSVersionName const FBOSVersionNameiOS_10_0 = @"iOS 10.0";
FBOSVersionName const FBOSVersionNameiOS_10_1 = @"iOS 10.1";
FBOSVersionName const FBOSVersionNameiOS_10_2 = @"iOS 10.2";
FBOSVersionName const FBOSVersionNameiOS_10_2_1 = @"iOS 10.2.1";
FBOSVersionName const FBOSVersionNameiOS_10_3 = @"iOS 10.3";
FBOSVersionName const FBOSVersionNameiOS_10_3_1 = @"iOS 10.3.1";
FBOSVersionName const FBOSVersionNameiOS_11_0 = @"iOS 11.0";
FBOSVersionName const FBOSVersionNameiOS_11_1 = @"iOS 11.1";
FBOSVersionName const FBOSVersionNameiOS_11_2 = @"iOS 11.2";
FBOSVersionName const FBOSVersionNameiOS_11_3 = @"iOS 11.3";
FBOSVersionName const FBOSVersionNameiOS_11_4 = @"iOS 11.4";
FBOSVersionName const FBOSVersionNameiOS_12_0 = @"iOS 12.0";
FBOSVersionName const FBOSVersionNameiOS_12_1 = @"iOS 12.1";
FBOSVersionName const FBOSVersionNameiOS_12_2 = @"iOS 12.2";
FBOSVersionName const FBOSVersionNameiOS_12_4 = @"iOS 12.4";
FBOSVersionName const FBOSVersionNameiOS_13_0 = @"iOS 13.0";
FBOSVersionName const FBOSVersionNameiOS_13_1 = @"iOS 13.1";
FBOSVersionName const FBOSVersionNameiOS_13_2 = @"iOS 13.2";
FBOSVersionName const FBOSVersionNameiOS_13_3 = @"iOS 13.3";
FBOSVersionName const FBOSVersionNameiOS_13_4 = @"iOS 13.4";
FBOSVersionName const FBOSVersionNameiOS_13_5 = @"iOS 13.5";
FBOSVersionName const FBOSVersionNameiOS_13_6 = @"iOS 13.6";
FBOSVersionName const FBOSVersionNameiOS_13_7 = @"iOS 13.7";
FBOSVersionName const FBOSVersionNameiOS_14_0 = @"iOS 14.0";
FBOSVersionName const FBOSVersionNameiOS_14_1 = @"iOS 14.1";
FBOSVersionName const FBOSVersionNameiOS_14_2 = @"iOS 14.2";
FBOSVersionName const FBOSVersionNameiOS_14_3 = @"iOS 14.3";
FBOSVersionName const FBOSVersionNameiOS_14_4 = @"iOS 14.4";
FBOSVersionName const FBOSVersionNameiOS_14_5 = @"iOS 14.5";
FBOSVersionName const FBOSVersionNametvOS_9_0 = @"tvOS 9.0";
FBOSVersionName const FBOSVersionNametvOS_9_1 = @"tvOS 9.1";
FBOSVersionName const FBOSVersionNametvOS_9_2 = @"tvOS 9.2";
FBOSVersionName const FBOSVersionNametvOS_10_0 = @"tvOS 10.0";
FBOSVersionName const FBOSVersionNametvOS_10_1 = @"tvOS 10.1";
FBOSVersionName const FBOSVersionNametvOS_10_2 = @"tvOS 10.2";
FBOSVersionName const FBOSVersionNametvOS_11_0 = @"tvOS 11.0";
FBOSVersionName const FBOSVersionNametvOS_11_1 = @"tvOS 11.1";
FBOSVersionName const FBOSVersionNametvOS_11_2 = @"tvOS 11.2";
FBOSVersionName const FBOSVersionNametvOS_11_3 = @"tvOS 11.3";
FBOSVersionName const FBOSVersionNametvOS_11_4 = @"tvOS 11.4";
FBOSVersionName const FBOSVersionNametvOS_12_0 = @"tvOS 12.0";
FBOSVersionName const FBOSVersionNametvOS_12_1 = @"tvOS 12.1";
FBOSVersionName const FBOSVersionNametvOS_12_2 = @"tvOS 12.2";
FBOSVersionName const FBOSVersionNametvOS_12_4 = @"tvOS 12.4";
FBOSVersionName const FBOSVersionNametvOS_13_0 = @"tvOS 13.0";
FBOSVersionName const FBOSVersionNametvOS_13_2 = @"tvOS 13.2";
FBOSVersionName const FBOSVersionNametvOS_13_3 = @"tvOS 13.3";
FBOSVersionName const FBOSVersionNametvOS_13_4 = @"tvOS 13.4";
FBOSVersionName const FBOSVersionNametvOS_14_0 = @"tvOS 14.0";
FBOSVersionName const FBOSVersionNametvOS_14_1 = @"tvOS 14.1";
FBOSVersionName const FBOSVersionNametvOS_14_2 = @"tvOS 14.2";
FBOSVersionName const FBOSVersionNametvOS_14_3 = @"tvOS 14.3";
FBOSVersionName const FBOSVersionNametvOS_14_5 = @"tvOS 14.5";
FBOSVersionName const FBOSVersionNamewatchOS_2_0 = @"watchOS 2.0";
FBOSVersionName const FBOSVersionNamewatchOS_2_1 = @"watchOS 2.1";
FBOSVersionName const FBOSVersionNamewatchOS_2_2 = @"watchOS 2.2";
FBOSVersionName const FBOSVersionNamewatchOS_3_0 = @"watchOS 3.0";
FBOSVersionName const FBOSVersionNamewatchOS_3_1 = @"watchOS 3.1";
FBOSVersionName const FBOSVersionNamewatchOS_3_2 = @"watchOS 3.2";
FBOSVersionName const FBOSVersionNamewatchOS_4_0 = @"watchOS 4.0";
FBOSVersionName const FBOSVersionNamewatchOS_4_1 = @"watchOS 4.1";
FBOSVersionName const FBOSVersionNamewatchOS_4_2 = @"watchOS 4.2";
FBOSVersionName const FBOSVersionNamewatchOS_5_0 = @"watchOS 5.0";
FBOSVersionName const FBOSVersionNamewatchOS_5_1 = @"watchOS 5.1";
FBOSVersionName const FBOSVersionNamewatchOS_5_2 = @"watchOS 5.2";
FBOSVersionName const FBOSVersionNamewatchOS_5_3 = @"watchOS 5.3";
FBOSVersionName const FBOSVersionNamewatchOS_6_0 = @"watchOS 6.0";
FBOSVersionName const FBOSVersionNamewatchOS_6_1 = @"watchOS 6.1";
FBOSVersionName const FBOSVersionNamewatchOS_6_2 = @"watchOS 6.2";
FBOSVersionName const FBOSVersionNamewatchOS_7_0 = @"watchOS 7.0";
FBOSVersionName const FBOSVersionNamewatchOS_7_1 = @"watchOS 7.1";
FBOSVersionName const FBOSVersionNamewatchOS_7_2 = @"watchOS 7.2";
FBOSVersionName const FBOSVersionNamewatchOS_7_4 = @"watchOS 7.4";

FBOSVersionName const FBOSVersionNamemac = @"macOS";

@implementation FBiOSTargetScreenInfo

- (instancetype)initWithWidthPixels:(NSUInteger)widthPixels heightPixels:(NSUInteger)heightPixels scale:(float)scale
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _widthPixels = widthPixels;
  _heightPixels = heightPixels;
  _scale = scale;

  return self;
}

- (BOOL)isEqual:(FBiOSTargetScreenInfo *)object
{
  if (![object isKindOfClass:FBiOSTargetScreenInfo.class]) {
    return NO;
  }
  return self.widthPixels == object.widthPixels && self.heightPixels == object.heightPixels && self.scale == object.scale;
}

- (NSUInteger)hash
{
  return self.widthPixels ^ self.heightPixels ^ (NSUInteger) self.scale;
}

- (id)copyWithZone:(NSZone *)zone
{
  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Screen Pixels %lu,%lu | Scale %fX", self.widthPixels, self.heightPixels, self.scale];
}

@end

@implementation FBDeviceType

#pragma mark Initializers

+ (instancetype)genericWithName:(NSString *)name
{
  return [[self alloc] initWithModel:name productTypes:NSSet.set deviceArchitecture:FBArchitectureArm64 family:FBControlCoreProductFamilyUnknown];
}

- (instancetype)initWithModel:(FBDeviceModel)model productTypes:(NSSet<NSString *> *)productTypes deviceArchitecture:(FBArchitecture)deviceArchitecture family:(FBControlCoreProductFamily)family
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _model = model;
  _productTypes = productTypes;
  _deviceArchitecture = deviceArchitecture;
  _family = family;

  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBDeviceType *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return [self.model isEqualToString:object.model];
}

- (NSUInteger)hash
{
  return self.model.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Model '%@'", self.model];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark Helpers

+ (instancetype)iPhoneWithModel:(FBDeviceModel)model productType:(NSString *)productType deviceArchitecture:(FBArchitecture)deviceArchitecture
{
  return [self iPhoneWithModel:model productTypes:@[productType] deviceArchitecture:deviceArchitecture];
}

+ (instancetype)iPhoneWithModel:(FBDeviceModel)model productTypes:(NSArray<NSString *> *)productTypes deviceArchitecture:(FBArchitecture)deviceArchitecture
{
  return [[self alloc] initWithModel:model productTypes:[NSSet setWithArray:productTypes] deviceArchitecture:deviceArchitecture family:FBControlCoreProductFamilyiPhone];
}

+ (instancetype)iPadWithModel:(FBDeviceModel)model productTypes:(NSArray<NSString *> *)productTypes deviceArchitecture:(FBArchitecture)deviceArchitecture
{
  return [[self alloc] initWithModel:model productTypes:[NSSet setWithArray:productTypes] deviceArchitecture:deviceArchitecture family:FBControlCoreProductFamilyiPad];
}

+ (instancetype)tvWithModel:(FBDeviceModel)model productTypes:(NSArray<NSString *> *)productTypes deviceArchitecture:(FBArchitecture)deviceArchitecture
{
  return [[self alloc] initWithModel:model productTypes:[NSSet setWithArray:productTypes] deviceArchitecture:deviceArchitecture family:FBControlCoreProductFamilyAppleTV];
}

+ (instancetype)watchWithModel:(FBDeviceModel)model productTypes:(NSArray<NSString *> *)productTypes deviceArchitecture:(FBArchitecture)deviceArchitecture
{
  return [[self alloc] initWithModel:model productTypes:[NSSet setWithArray:productTypes] deviceArchitecture:deviceArchitecture family:FBControlCoreProductFamilyAppleWatch];
}

+ (instancetype)genericWithModel:(NSString *)model
{
  return [[self alloc] initWithModel:model productTypes:[NSSet set] deviceArchitecture:FBArchitectureArm64 family:FBControlCoreProductFamilyUnknown];
}

@end

#pragma mark OS Versions

@implementation FBOSVersion

#pragma mark Initializers

+ (instancetype)genericWithName:(NSString *)name
{
  return [[self alloc] initWithName:name families:NSSet.set];
}

- (instancetype)initWithName:(FBOSVersionName)name families:(NSSet<NSNumber *> *)families
{
  self = [super init];
  if (!self){
    return nil;
  }

  _name = name;
  _families = families;

  return self;
}

#pragma mark Public

+ (NSOperatingSystemVersion)operatingSystemVersionFromName:(NSString *)name
{
  NSArray<NSString *> *components = [name componentsSeparatedByCharactersInSet:NSCharacterSet.punctuationCharacterSet];
  NSOperatingSystemVersion version = {
    .majorVersion = 0,
    .minorVersion = 0,
    .patchVersion = 0,
  };
  for (NSUInteger index = 0; index < components.count; index++) {
    NSInteger value = components[index].integerValue;
    switch (index) {
      case 0:
        version.majorVersion = value;
        continue;
      case 1:
        version.minorVersion = value;
        continue;
      case 2:
        version.patchVersion = value;
        continue;
      default:
        continue;
    }
  }
  return version;
}


#pragma mark NSObject

// Version String implies uniqueness
- (BOOL)isEqual:(FBOSVersion *)version
{
  if (![version isKindOfClass:self.class]) {
    return NO;
  }

  return [self.name isEqualToString:version.name];
}

- (NSUInteger)hash
{
  return self.name.hash;
}

- (NSDecimalNumber *)number
{
  return [NSDecimalNumber decimalNumberWithString:self.versionString];
}

- (NSOperatingSystemVersion)version
{
  return [FBOSVersion operatingSystemVersionFromName:self.versionString];
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"OS '%@'", self.name];
}

- (NSString *)versionString
{
  return [self.name componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet][1];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Object is immutable
  return self;
}

#pragma mark Helpers

+ (instancetype)iOSWithName:(FBOSVersionName)name
{
  NSSet *families = [NSSet setWithArray:@[
    @(FBControlCoreProductFamilyiPhone),
    @(FBControlCoreProductFamilyiPad),
  ]];
  return [[self alloc] initWithName:name families:families];
}

+ (instancetype)tvOSWithName:(FBOSVersionName)name
{
  return [[self alloc] initWithName:name families:[NSSet setWithObject:@(FBControlCoreProductFamilyAppleTV)]];
}

+ (instancetype)watchOSWithName:(FBOSVersionName)name
{
  return [[self alloc] initWithName:name families:[NSSet setWithObject:@(FBControlCoreProductFamilyAppleWatch)]];
}

+ (instancetype)macOSWithName:(FBOSVersionName)name
{
  return [[self alloc] initWithName:name families:[NSSet setWithObject:@(FBControlCoreProductFamilyMac)]];
}

@end

@implementation FBiOSTargetConfiguration

#pragma mark Lookup Tables

+ (NSArray<FBDeviceType *> *)deviceConfigurations
{
  static dispatch_once_t onceToken;
  static NSArray<FBDeviceType *> *deviceConfigurations;
  dispatch_once(&onceToken, ^{
    deviceConfigurations = @[
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone4s productType:@"iPhone4,1" deviceArchitecture:FBArchitectureArmv7],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone5 productTypes:@[@"iPhone5,1", @"iPhone5,2"] deviceArchitecture:FBArchitectureArmv7s],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone5c productTypes:@[@"iPhone5,3"] deviceArchitecture:FBArchitectureArmv7s],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone5s productTypes:@[@"iPhone6,1", @"iPhone6,2"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone6 productType:@"iPhone7,2" deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone6Plus productType:@"iPhone7,1" deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone6S productType:@"iPhone8,1" deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone6SPlus productType:@"iPhone8,2" deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhoneSE_1stGeneration productType:@"iPhone8,4" deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhoneSE_2ndGeneration productType:@"iPhone12,8" deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone7 productTypes:@[@"iPhone9,1", @"iPhone9,2", @"iPhone9,3"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone7Plus productTypes:@[@"iPhone9,2", @"iPhone9,4"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone8 productTypes:@[@"iPhone10,1", @"iPhone10,4"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone8Plus productTypes:@[@"iPhone10,2", @"iPhone10,5"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhoneX productTypes:@[@"iPhone10,3", @"iPhone10,6"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhoneXs productTypes:@[@"iPhone11,2"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhoneXsMax productTypes:@[@"iPhone11,6"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhoneXr productTypes:@[@"iPhone11,8"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone11 productTypes:@[@"iPhone12,1"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone11Pro productTypes:@[@"iPhone12,3"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone11ProMax productTypes:@[@"iPhone12,5"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone12mini productTypes:@[@"iPhone13,1"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone12 productTypes:@[@"iPhone13,2"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone12Pro productTypes:@[@"iPhone13,3"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone12ProMax productTypes:@[@"iPhone13,4"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone13mini productTypes:@[@"iPhone14,4"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone13 productTypes:@[@"iPhone14,5"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone13Pro productTypes:@[@"iPhone14,2"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone13ProMax productTypes:@[@"iPhone14,3"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone14 productTypes:@[@"iPhone14,7"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone14Plus productTypes:@[@"iPhone14,8"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone14Pro productTypes:@[@"iPhone15,2"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone14ProMax productTypes:@[@"iPhone15,3"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone15 productTypes:@[@"iPhone15,4"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone15Plus productTypes:@[@"iPhone15,5"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone15Pro productTypes:@[@"iPhone16,1"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPhone15ProMax productTypes:@[@"iPhone16,2"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPhoneWithModel:FBDeviceModeliPodTouch_7thGeneration productTypes:@[@"iPod9,1"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPad2 productTypes:@[@"iPad2,1", @"iPad2,2", @"iPad2,3", @"iPad2,4"] deviceArchitecture:FBArchitectureArmv7],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadRetina productTypes:@[@"iPad3,1", @"iPad3,2", @"iPad3,3", @"iPad3,4", @"iPad3,5", @"iPad3,6"] deviceArchitecture:FBArchitectureArmv7],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadAir productTypes:@[@"iPad4,1", @"iPad4,2", @"iPad4,3"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadAir2 productTypes:@[@"iPad5,3", @"iPad5,4"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadAir_3rdGeneration productTypes:@[@"iPad11,3", @"iPad11,4"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadAir_4thGeneration productTypes:@[@"iPad13,1", @"iPad13,2"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadPro productTypes:@[@"iPad6,7", @"iPad6,8", @"iPad6,3", @"iPad6,4"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadPro_9_7_Inch productTypes:@[@"iPad6,3", @"iPad6,4"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadPro_12_9_Inch productTypes:@[@"iPad6,7", @"iPad6,8"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPad_5thGeneration productTypes:@[@"iPad6,11", @"iPad6,12"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadPro_12_9_Inch_2ndGeneration productTypes:@[@"iPad7,1", @"iPad7,2"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadPro_10_5_Inch productTypes:@[@"iPad7,3", @"iPad7,4"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPad_6thGeneration productTypes:@[@"iPad7,5", @"iPad7,6"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPad_7thGeneration productTypes:@[@"iPad7,11", @"iPad7,12"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPad_8thGeneration productTypes:@[@"iPad11,6", @"iPad11,7"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadPro_12_9_Inch_3rdGeneration productTypes:@[@"iPad8,5", @"iPad8,6", @"iPad8,7", @"iPad8,8"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadPro_12_9_Inch_4thGeneration productTypes:@[@"iPad8,11", @"iPad8,12"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadPro_11_Inch_1stGeneration productTypes:@[@"iPad8,1", @"iPad8,2", @"iPad8,3", @"iPad8,4"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadPro_12_9nch_1stGeneration productTypes:@[@"iPad8,11", @"iPad8,12"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadPro_12_9nch_5thGeneration productTypes:@[@"iPad13,8", @"iPad13,9", @"iPad13,10", @"iPad13,11"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadPro_11_Inch_2ndGeneration productTypes:@[@"iPad8,9", @"iPad8,10"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadPro_11_Inch_3ndGeneration productTypes:@[@"iPad13,4", @"iPad13,5", @"iPad13,6", @"iPad13,7"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadMini_2 productTypes:@[@"iPad4,4", @"iPad4,5", @"iPad4,6",] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadMini_3 productTypes:@[@"iPad4,7", @"iPad4,8", @"iPad4,9"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadMini_4 productTypes:@[@"iPad5,1", @"iPad5,2"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType iPadWithModel:FBDeviceModeliPadMini_5 productTypes:@[@"iPad11,1", @"iPad11,2"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType tvWithModel:FBDeviceModelAppleTV productTypes:@[@"AppleTV5,3"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType tvWithModel:FBDeviceModelAppleTV4K productTypes:@[@"AppleTV6,2"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType tvWithModel:FBDeviceModelAppleTV4KAt1080p productTypes:@[@"AppleTV6,2"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType tvWithModel:FBDeviceModelAppleTV4K_2ndGeneration productTypes:@[@"AppleTV11,1"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType tvWithModel:FBDeviceModelAppleTV4KAt1080p_2ndGeneration productTypes:@[@"AppleTV11,1"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType watchWithModel:FBDeviceModelAppleWatch38mm productTypes:@[@"Watch1,1"] deviceArchitecture:FBArchitectureArmv7],
      [FBDeviceType watchWithModel:FBDeviceModelAppleWatch42mm productTypes:@[@"Watch1,2"] deviceArchitecture:FBArchitectureArmv7],
      [FBDeviceType watchWithModel:FBDeviceModelAppleWatchSE_40mm productTypes:@[@"Watch1,1"] deviceArchitecture:FBArchitectureArmv7],
      [FBDeviceType watchWithModel:FBDeviceModelAppleWatchSE_44mm productTypes:@[@"Watch1,2"] deviceArchitecture:FBArchitectureArmv7],
      [FBDeviceType watchWithModel:FBDeviceModelAppleWatchSeries2_38mm productTypes:@[@"Watch2,1"] deviceArchitecture:FBArchitectureArmv7],
      [FBDeviceType watchWithModel:FBDeviceModelAppleWatchSeries2_42mm productTypes:@[@"Watch2,2"] deviceArchitecture:FBArchitectureArmv7],
      [FBDeviceType watchWithModel:FBDeviceModelAppleWatchSeries3_38mm productTypes:@[@"Watch3,1"] deviceArchitecture:FBArchitectureArmv7],
      [FBDeviceType watchWithModel:FBDeviceModelAppleWatchSeries3_42mm productTypes:@[@"Watch3,2"] deviceArchitecture:FBArchitectureArmv7],
      [FBDeviceType watchWithModel:FBDeviceModelAppleWatchSeries4_40mm productTypes:@[@"Watch4,1", @"Watch4,3"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType watchWithModel:FBDeviceModelAppleWatchSeries4_44mm productTypes:@[@"Watch4,2", @"Watch4,4"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType watchWithModel:FBDeviceModelAppleWatchSeries5_40mm productTypes:@[@"Watch5,1", @"Watch5,3"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType watchWithModel:FBDeviceModelAppleWatchSeries5_44mm productTypes:@[@"Watch5,2", @"Watch5,4"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType watchWithModel:FBDeviceModelAppleWatchSeries6_40mm productTypes:@[@"Watch6,1", @"Watch6,3"] deviceArchitecture:FBArchitectureArm64],
      [FBDeviceType watchWithModel:FBDeviceModelAppleWatchSeries6_44mm productTypes:@[@"Watch6,2", @"Watch6,4"] deviceArchitecture:FBArchitectureArm64],

    ];
  });
  return deviceConfigurations;
}

+ (NSArray<FBOSVersion *> *)OSConfigurations
{
  static dispatch_once_t onceToken;
  static NSArray<FBOSVersion *> *OSConfigurations;
  dispatch_once(&onceToken, ^{
    OSConfigurations = @[
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_7_1],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_8_0],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_8_1],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_8_2],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_8_3],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_8_4],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_9_0],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_9_1],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_9_2],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_9_3],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_9_3_1],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_9_3_2],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_10_0],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_10_1],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_10_2],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_10_2_1],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_10_3],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_10_3_1],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_11_0],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_11_1],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_11_2],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_11_3],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_11_4],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_11_4],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_12_0],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_12_1],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_12_2],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_12_4],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_13_0],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_13_1],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_13_2],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_13_3],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_13_4],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_13_5],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_13_6],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_13_7],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_14_0],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_14_1],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_14_2],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_14_3],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_14_4],
      [FBOSVersion iOSWithName:FBOSVersionNameiOS_14_5],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_9_0],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_9_1],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_9_2],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_10_0],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_10_1],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_10_2],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_11_0],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_11_1],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_11_2],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_11_3],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_11_4],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_12_0],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_12_1],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_12_2],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_12_4],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_13_0],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_13_2],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_13_3],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_13_4],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_14_0],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_14_1],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_14_2],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_14_3],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_14_5],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_2_0],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_2_1],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_2_2],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_3_0],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_3_1],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_3_2],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_4_0],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_4_1],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_4_2],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_5_0],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_5_1],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_5_2],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_5_3],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_6_0],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_6_1],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_6_2],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_7_0],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_7_1],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_7_2],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_7_4],
      [FBOSVersion macOSWithName:FBOSVersionNamemac],
    ];
  });
  return OSConfigurations;
}

+ (NSDictionary<FBDeviceModel, FBDeviceType *> *)nameToDevice
{
  static dispatch_once_t onceToken;
  static NSDictionary<FBDeviceModel, FBDeviceType *> *mapping;
  dispatch_once(&onceToken, ^{
    NSArray *instances = self.deviceConfigurations;
    NSMutableDictionary<FBDeviceModel, FBDeviceType *> *dictionary = [NSMutableDictionary dictionary];
    for (FBDeviceType *device in instances) {
      dictionary[device.model] = device;
    }
    mapping = [dictionary copy];
  });
  return mapping;
}

+ (NSDictionary<NSString *, FBDeviceType *> *)productTypeToDevice
{
  static dispatch_once_t onceToken;
  static NSDictionary<NSString *, FBDeviceType *> *mapping;
  dispatch_once(&onceToken, ^{
    NSArray *instances = self.deviceConfigurations;
    NSMutableDictionary<NSString *, FBDeviceType *> *dictionary = [NSMutableDictionary dictionary];
    for (FBDeviceType *device in instances) {
      for (NSString *productType in device.productTypes) {
        dictionary[productType] = device;
      }
    }
    mapping = [dictionary copy];
  });
  return mapping;
}

+ (NSDictionary<FBOSVersionName, FBOSVersion *> *)nameToOSVersion
{
  static dispatch_once_t onceToken;
  static NSDictionary<FBOSVersionName, FBOSVersion *> *mapping;
  dispatch_once(&onceToken, ^{
    NSArray *instances = self.OSConfigurations;
    NSMutableDictionary<FBOSVersionName, FBOSVersion *> *dictionary = [NSMutableDictionary dictionary];
    for (FBOSVersion *os in instances) {
      dictionary[os.name] = os;
    }
    mapping = [dictionary copy];
  });
  return mapping;
}

+ (NSSet<FBArchitecture> *)baseArchsToCompatibleArch:(NSArray<FBArchitecture>*)architectures
{

  NSDictionary<FBArchitecture, NSSet<FBArchitecture> *> *mapping = @{
    FBArchitectureArm64e : [NSSet setWithArray:@[FBArchitectureArm64e, FBArchitectureArm64, FBArchitectureArmv7s, FBArchitectureArmv7]],
    FBArchitectureArm64 : [NSSet setWithArray:@[FBArchitectureArm64, FBArchitectureArmv7s, FBArchitectureArmv7]],
    FBArchitectureArmv7s : [NSSet setWithArray:@[FBArchitectureArmv7s, FBArchitectureArmv7]],
    FBArchitectureArmv7 : [NSSet setWithArray:@[FBArchitectureArmv7]],
    FBArchitectureI386 : [NSSet setWithObject:FBArchitectureI386],
    FBArchitectureX86_64 : [NSSet setWithArray:@[FBArchitectureX86_64, FBArchitectureI386]],
  };

  NSMutableSet<FBArchitecture> *result = [NSMutableSet new];
  for (FBArchitecture arch in architectures) {
    [result unionSet:mapping[arch]];
  }
  return result;
}

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBControlCoreConfigurationVariants.h"

#import "FBArchitecture.h"

FBDeviceName const FBDeviceNameiPhone4s = @"iPhone 4s";
FBDeviceName const FBDeviceNameiPhone5 = @"iPhone 5";
FBDeviceName const FBDeviceNameiPhone5s = @"iPhone 5s";
FBDeviceName const FBDeviceNameiPhone6 = @"iPhone 6";
FBDeviceName const FBDeviceNameiPhone6Plus = @"iPhone 6 Plus";
FBDeviceName const FBDeviceNameiPhone6S = @"iPhone 6s";
FBDeviceName const FBDeviceNameiPhone6SPlus = @"iPhone 6s Plus";
FBDeviceName const FBDeviceNameiPhoneSE = @"iPhone SE";
FBDeviceName const FBDeviceNameiPhone7 = @"iPhone 7";
FBDeviceName const FBDeviceNameiPhone7Plus = @"iPhone 7 Plus";
FBDeviceName const FBDeviceNameiPad2 = @"iPad 2";
FBDeviceName const FBDeviceNameiPadRetina = @"iPad Retina";
FBDeviceName const FBDeviceNameiPadAir = @"iPad Air";
FBDeviceName const FBDeviceNameiPadAir2 = @"iPad Air 2";
FBDeviceName const FBDeviceNameiPadPro = @"iPad Pro";
FBDeviceName const FBDeviceNameiPadPro_9_7_Inch = @"iPad Pro (9.7-inch)";
FBDeviceName const FBDeviceNameiPadPro_12_9_Inch = @"iPad Pro (12.9-inch)";
FBDeviceName const FBDeviceNameAppleTV1080p = @"Apple TV 1080p";
FBDeviceName const FBDeviceNameAppleWatch38mm = @"Apple Watch - 38mm";
FBDeviceName const FBDeviceNameAppleWatch42mm = @"Apple Watch - 42mm";
FBDeviceName const FBDeviceNameAppleWatchSeries2_38mm = @"Apple Watch Series 2 - 38mm";
FBDeviceName const FBDeviceNameAppleWatchSeries2_42mm = @"Apple Watch Series 2 - 42mm";

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
FBOSVersionName const FBOSVersionNametvOS_9_0 = @"tvOS 9.0";
FBOSVersionName const FBOSVersionNametvOS_9_1 = @"tvOS 9.1";
FBOSVersionName const FBOSVersionNametvOS_9_2 = @"tvOS 9.2";
FBOSVersionName const FBOSVersionNametvOS_10_0 = @"tvOS 10.0";
FBOSVersionName const FBOSVersionNametvOS_10_1 = @"tvOS 10.1";
FBOSVersionName const FBOSVersionNametvOS_10_2 = @"tvOS 10.2";
FBOSVersionName const FBOSVersionNamewatchOS_2_0 = @"watchOS 2.0";
FBOSVersionName const FBOSVersionNamewatchOS_2_1 = @"watchOS 2.1";
FBOSVersionName const FBOSVersionNamewatchOS_2_2 = @"watchOS 2.2";
FBOSVersionName const FBOSVersionNamewatchOS_3_0 = @"watchOS 3.0";
FBOSVersionName const FBOSVersionNamewatchOS_3_1 = @"watchOS 3.1";
FBOSVersionName const FBOSVersionNamewatchOS_3_2 = @"watchOS 3.2";

@implementation FBControlCoreConfigurationVariant_Base

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  // Only needs to be implemented to encode the classes
  // Each instance of a FBControlCoreConfigurationVariant has no state
  // So no state will need to be encoded.
}

#pragma mark NSObject

- (BOOL)isEqual:(NSObject *)object
{
  return [object isMemberOfClass:self.class];
}

- (NSUInteger)hash
{
  return [NSStringFromClass(self.class) hash];
}

- (NSString *)description
{
  return NSStringFromClass(self.class);
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

@end

#pragma mark Families

@implementation FBControlCoreConfiguration_Family_iPhone

- (FBControlCoreProductFamily)productFamilyID
{
  return FBControlCoreProductFamilyiPhone;
}

@end

@implementation FBControlCoreConfiguration_Family_iPad

- (FBControlCoreProductFamily)productFamilyID
{
  return FBControlCoreProductFamilyiPad;
}

@end

@implementation FBControlCoreConfiguration_Family_TV

- (FBControlCoreProductFamily)productFamilyID
{
  return FBControlCoreProductFamilyAppleTV;
}

@end

@implementation FBControlCoreConfiguration_Family_Watch

- (FBControlCoreProductFamily)productFamilyID
{
  return FBControlCoreProductFamilyAppleWatch;
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone_Base

- (FBDeviceName)deviceName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSSet<NSString *> *)productTypes
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBArchitecture)deviceArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBArchitecture)simulatorArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id<FBControlCoreConfiguration_Family>)family
{
  return FBControlCoreConfiguration_Family_iPhone.new;
}

@end

#pragma mark Devices

@implementation FBControlCoreConfiguration_Device_iPhone4s

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPhone4s;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone4,1"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArmv7;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureI386;
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone5

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPhone5;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone5,1", @"iPhone5,2"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArmv7s;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureI386;
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone5s

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPhone5s;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone6,1", @"iPhone6,2"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArm64;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureX86_64;
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone6

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPhone6;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone7,2"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArm64;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureX86_64;
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone6Plus

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPhone6Plus;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone7,1"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArm64;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureX86_64;
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone6S

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPhone6S;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone8,1"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArm64;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureX86_64;
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone6SPlus

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPhone6SPlus;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone8,2"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArm64;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureX86_64;
}

@end

@implementation FBControlCoreConfiguration_Device_iPhoneSE

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPhoneSE;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone8,4"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArm64;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureX86_64;
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone7

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPhone7;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone9,1", @"iPhone9,3"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArm64;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureX86_64;
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone7Plus

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPhone7Plus;
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArm64;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone9,2", @"iPhone9,4"]];
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureX86_64;
}

@end

@implementation FBControlCoreConfiguration_Device_iPad_Base

- (FBDeviceName)deviceName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSSet<NSString *> *)productTypes
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBArchitecture)deviceArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBArchitecture)simulatorArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id<FBControlCoreConfiguration_Family>)family
{
  return FBControlCoreConfiguration_Family_iPad.new;
}

@end

@implementation FBControlCoreConfiguration_Device_iPad2

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPad2;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPad2,1", @"iPad2,2", @"iPad2,3", @"iPad2,4"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArmv7;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureI386;
}

@end

@implementation FBControlCoreConfiguration_Device_iPadRetina

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPadRetina;
}

- (NSSet<NSString *> *)productTypes
{
  // Both 'iPad 3' and 'iPad 4'.
  return [NSSet setWithArray:@[@"iPad3,1", @"iPad3,2", @"iPad3,3", @"iPad3,4", @"iPad3,5", @"iPad3,6"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArmv7;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureI386;
}

@end

@implementation FBControlCoreConfiguration_Device_iPadAir

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPadAir;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPad4,1", @"iPad4,2", @"iPad4,3"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArm64;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureX86_64;
}

@end

@implementation FBControlCoreConfiguration_Device_iPadAir2

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPadAir2;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPad5,3", @"iPad5,4"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArm64;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureX86_64;
}

@end

@implementation FBControlCoreConfiguration_Device_iPadPro

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPadPro;
}

- (NSSet<NSString *> *)productTypes
{
  // Both the 9" and 12" Variants.
  return [NSSet setWithArray:@[@"iPad6,7", @"iPad6,8", @"iPad6,3", @"iPad6,4"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArm64;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureX86_64;
}

@end

@implementation FBControlCoreConfiguration_Device_iPadPro_9_7_Inch

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPadPro_9_7_Inch;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPad6,3", @"iPad6,4"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArm64;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureX86_64;
}

@end

@implementation  FBControlCoreConfiguration_Device_iPadPro_12_9_Inch

- (FBDeviceName)deviceName
{
  return FBDeviceNameiPadPro_12_9_Inch;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPad6,7", @"iPad6,8"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArm64;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureX86_64;
}

@end

@implementation FBControlCoreConfiguration_Device_tvOS_Base

- (FBDeviceName)deviceName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSSet<NSString *> *)productTypes
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBArchitecture)deviceArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBArchitecture)simulatorArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id<FBControlCoreConfiguration_Family>)family
{
  return FBControlCoreConfiguration_Family_TV.new;
}

@end

@implementation FBControlCoreConfiguration_Device_AppleTV1080p

- (FBDeviceName)deviceName
{
  return FBDeviceNameAppleTV1080p;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"AppleTV5,3"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArm64;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureX86_64;
}

@end

@implementation FBControlCoreConfiguration_Device_watchOS_Base

- (FBDeviceName)deviceName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSSet<NSString *> *)productTypes
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBArchitecture)deviceArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBArchitecture)simulatorArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id<FBControlCoreConfiguration_Family>)family
{
  return FBControlCoreConfiguration_Family_Watch.new;
}

@end

@implementation FBControlCoreConfiguration_Device_AppleWatch38mm

- (FBDeviceName)deviceName
{
  return FBDeviceNameAppleWatch38mm;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"Watch1,1"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArmv7;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureI386;
}

@end

@implementation FBControlCoreConfiguration_Device_AppleWatch42mm

- (FBDeviceName)deviceName
{
  return FBDeviceNameAppleWatch42mm;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"Watch1,2"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArmv7;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureI386;
}

@end

@implementation FBControlCoreConfiguration_Device_AppleWatchSeries2_38mm

- (FBDeviceName)deviceName
{
  return FBDeviceNameAppleWatchSeries2_38mm;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"Watch2,1"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArmv7;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureI386;
}

@end

@implementation FBControlCoreConfiguration_Device_AppleWatchSeries2_42mm

- (FBDeviceName)deviceName
{
  return FBDeviceNameAppleWatchSeries2_42mm;
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"Watch2,2"]];
}

- (FBArchitecture)deviceArchitecture
{
  return FBArchitectureArmv7;
}

- (FBArchitecture)simulatorArchitecture
{
  return FBArchitectureI386;
}

@end

#pragma mark OS Versions

@implementation FBOSVersion

- (instancetype)initWithName:(FBOSVersionName)name families:(NSSet<id<FBControlCoreConfiguration_Family>> *)families
{
  self = [super init];
  if (!self){
    return nil;
  }

  _name = name;
  _families = families;

  return self;
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

- (NSDecimalNumber *)versionNumber
{
  NSString *versionString = [self.name componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet][1];
  return [NSDecimalNumber decimalNumberWithString:versionString];
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
    FBControlCoreConfiguration_Family_iPhone.new,
    FBControlCoreConfiguration_Family_iPad.new,
  ]];
  return [[self alloc] initWithName:name families:families];
}

+ (instancetype)genericWithName:(NSString *)name
{
  return [[self alloc] initWithName:name families:NSSet.set];
}

+ (instancetype)tvOSWithName:(FBOSVersionName)name
{
  return [[self alloc] initWithName:name families:[NSSet setWithObject:FBControlCoreConfiguration_Family_TV.new]];
}

+ (instancetype)watchOSWithName:(FBOSVersionName)name
{
  return [[self alloc] initWithName:name families:[NSSet setWithObject:FBControlCoreConfiguration_Family_Watch.new]];
}

@end

@implementation FBControlCoreConfigurationVariants

#pragma mark Lookup Tables

+ (NSArray<id<FBControlCoreConfiguration_Device>> *)deviceConfigurations
{
  static dispatch_once_t onceToken;
  static NSArray<id<FBControlCoreConfiguration_Device>> *deviceConfigurations;
  dispatch_once(&onceToken, ^{
    deviceConfigurations = @[
      FBControlCoreConfiguration_Device_iPhone4s.new,
      FBControlCoreConfiguration_Device_iPhone5.new,
      FBControlCoreConfiguration_Device_iPhone5s.new,
      FBControlCoreConfiguration_Device_iPhone6.new,
      FBControlCoreConfiguration_Device_iPhone6Plus.new,
      FBControlCoreConfiguration_Device_iPhone6S.new,
      FBControlCoreConfiguration_Device_iPhone6SPlus.new,
      FBControlCoreConfiguration_Device_iPhoneSE.new,
      FBControlCoreConfiguration_Device_iPhone7.new,
      FBControlCoreConfiguration_Device_iPhone7Plus.new,
      FBControlCoreConfiguration_Device_iPad2.new,
      FBControlCoreConfiguration_Device_iPadRetina.new,
      FBControlCoreConfiguration_Device_iPadAir.new,
      FBControlCoreConfiguration_Device_iPadPro.new,
      FBControlCoreConfiguration_Device_iPadPro_9_7_Inch.new,
      FBControlCoreConfiguration_Device_iPadPro_12_9_Inch.new,
      FBControlCoreConfiguration_Device_iPadAir2.new,
      FBControlCoreConfiguration_Device_AppleWatch38mm.new,
      FBControlCoreConfiguration_Device_AppleWatch42mm.new,
      FBControlCoreConfiguration_Device_AppleTV1080p.new,
      FBControlCoreConfiguration_Device_AppleWatchSeries2_38mm.new,
      FBControlCoreConfiguration_Device_AppleWatchSeries2_42mm.new,
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
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_9_0],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_9_1],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_9_2],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_10_0],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_10_1],
      [FBOSVersion tvOSWithName:FBOSVersionNametvOS_10_2],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_2_0],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_2_1],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_2_2],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_3_0],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_3_1],
      [FBOSVersion tvOSWithName:FBOSVersionNamewatchOS_3_2]
    ];
  });
  return OSConfigurations;
}

+ (NSDictionary<FBDeviceName, id<FBControlCoreConfiguration_Device>> *)nameToDevice
{
  static dispatch_once_t onceToken;
  static NSDictionary<FBDeviceName, id<FBControlCoreConfiguration_Device>> *mapping;
  dispatch_once(&onceToken, ^{
    NSArray *instances = self.deviceConfigurations;
    NSMutableDictionary<FBDeviceName, id<FBControlCoreConfiguration_Device>> *dictionary = [NSMutableDictionary dictionary];
    for (id<FBControlCoreConfiguration_Device> device in instances) {
      dictionary[device.deviceName] = device;
    }
    mapping = [dictionary copy];
  });
  return mapping;
}

+ (NSDictionary<NSString *, id<FBControlCoreConfiguration_Device>> *)productTypeToDevice
{
  static dispatch_once_t onceToken;
  static NSDictionary<NSString *, id<FBControlCoreConfiguration_Device>> *mapping;
  dispatch_once(&onceToken, ^{
    NSArray *instances = self.deviceConfigurations;
    NSMutableDictionary<NSString *, id<FBControlCoreConfiguration_Device>> *dictionary = [NSMutableDictionary dictionary];
    for (id<FBControlCoreConfiguration_Device> device in instances) {
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

+ (NSDictionary<FBArchitecture, NSSet<FBArchitecture> *> *)baseArchToCompatibleArch
{
  return @{
    FBArchitectureArm64 : [NSSet setWithArray:@[FBArchitectureArm64, FBArchitectureArmv7s, FBArchitectureArmv7]],
    FBArchitectureArmv7s : [NSSet setWithArray:@[FBArchitectureArmv7s, FBArchitectureArmv7]],
    FBArchitectureArmv7 : [NSSet setWithArray:@[FBArchitectureArmv7]],
    FBArchitectureI386 : [NSSet setWithObject:FBArchitectureI386],
    FBArchitectureX86_64 : [NSSet setWithArray:@[FBArchitectureX86_64, FBArchitectureI386]],
  };
}

@end

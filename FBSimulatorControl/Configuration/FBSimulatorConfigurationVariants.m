/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorConfigurationVariants.h"

@implementation FBSimulatorConfigurationVariant_Base

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
  // Each instance of a FBSimulatorConfigurationVariant has no state
  // So no state will need to be encoded.
}

#pragma mark NSObject

- (BOOL)isEqual:(NSObject *)object
{
  return [self.class isEqual:object.class];
}

- (NSUInteger)hash
{
  return [NSStringFromClass(self.class) hash];
}

- (NSString *)description
{
  return NSStringFromClass(self.class);
}

@end

#pragma mark Families

@implementation FBSimulatorConfiguration_Family_iPhone

- (FBSimulatorProductFamily)productFamilyID
{
  return FBSimulatorProductFamilyiPhone;
}

@end

@implementation FBSimulatorConfiguration_Family_iPad

- (FBSimulatorProductFamily)productFamilyID
{
  return FBSimulatorProductFamilyiPad;
}

@end

@implementation FBSimulatorConfiguration_Family_TV

- (FBSimulatorProductFamily)productFamilyID
{
  return FBSimulatorProductFamilyAppleTV;
}

@end

@implementation FBSimulatorConfiguration_Family_Watch

- (FBSimulatorProductFamily)productFamilyID
{
  return FBSimulatorProductFamilyAppleWatch;
}

@end

@implementation FBSimulatorConfiguration_Device_iPhone_Base

- (NSString *)deviceName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id<FBSimulatorConfiguration_Family>)family
{
  return FBSimulatorConfiguration_Family_iPhone.new;
}

@end

#pragma mark Devices

@implementation FBSimulatorConfiguration_Device_iPhone4s

- (NSString *)deviceName
{
  return @"iPhone 4s";
}

@end

@implementation FBSimulatorConfiguration_Device_iPhone5

- (NSString *)deviceName
{
  return @"iPhone 5";
}

@end

@implementation FBSimulatorConfiguration_Device_iPhone5s

- (NSString *)deviceName
{
  return @"iPhone 5s";
}

@end

@implementation FBSimulatorConfiguration_Device_iPhone6

- (NSString *)deviceName
{
  return @"iPhone 6";
}

@end

@implementation FBSimulatorConfiguration_Device_iPhone6Plus

- (NSString *)deviceName
{
  return @"iPhone 6 Plus";
}

@end

@implementation FBSimulatorConfiguration_Device_iPhone6S

- (NSString *)deviceName
{
  return @"iPhone 6s";
}

@end

@implementation FBSimulatorConfiguration_Device_iPhone6SPlus

- (NSString *)deviceName
{
  return @"iPhone 6s Plus";
}

@end

@implementation FBSimulatorConfiguration_Device_iPad_Base

- (NSString *)deviceName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id<FBSimulatorConfiguration_Family>)family
{
  return FBSimulatorConfiguration_Family_iPad.new;
}

@end

@implementation FBSimulatorConfiguration_Device_iPad2

- (NSString *)deviceName
{
  return @"iPad 2";
}

@end

@implementation FBSimulatorConfiguration_Device_iPadRetina

- (NSString *)deviceName
{
  return @"iPad Retina";
}

@end

@implementation FBSimulatorConfiguration_Device_iPadAir

- (NSString *)deviceName
{
  return @"iPad Air";
}

@end

@implementation FBSimulatorConfiguration_Device_iPadAir2

- (NSString *)deviceName
{
  return @"iPad Air 2";
}

@end

@implementation FBSimulatorConfiguration_Device_iPadPro

- (NSString *)deviceName
{
  return @"iPad Pro";
}

@end

@implementation FBSimulatorConfiguration_Device_tvOS_Base

- (NSString *)deviceName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id<FBSimulatorConfiguration_Family>)family
{
  return FBSimulatorConfiguration_Family_TV.new;
}

@end

@implementation FBSimulatorConfiguration_Device_AppleTV1080p

- (NSString *)deviceName
{
  return @"Apple TV 1080p";
}

@end

@implementation FBSimulatorConfiguration_Device_watchOS_Base

- (NSString *)deviceName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id<FBSimulatorConfiguration_Family>)family
{
  return FBSimulatorConfiguration_Family_Watch.new;
}

@end

@implementation FBSimulatorConfiguration_Device_AppleWatch38mm

- (NSString *)deviceName
{
  return @"Apple Watch - 38mm";
}

@end

@implementation FBSimulatorConfiguration_Device_AppleWatch42mm

- (NSString *)deviceName
{
  return @"Apple Watch - 42mm";
}

@end

#pragma mark OS Versions

@implementation FBSimulatorConfiguration_iOS_Base

- (NSString *)name
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSSet *)families
{
  return [NSSet setWithArray:@[
    FBSimulatorConfiguration_Family_iPhone.new,
    FBSimulatorConfiguration_Family_iPad.new,
  ]];
}

@end

@implementation FBSimulatorConfiguration_iOS_7_1

- (NSString *)name
{
  return @"iOS 7.1";
}

@end

@implementation FBSimulatorConfiguration_iOS_8_0

- (NSString *)name
{
  return @"iOS 8.0";
}

@end

@implementation FBSimulatorConfiguration_iOS_8_1

- (NSString *)name
{
  return @"iOS 8.1";
}

@end

@implementation FBSimulatorConfiguration_iOS_8_2

- (NSString *)name
{
  return @"iOS 8.2";
}

@end

@implementation FBSimulatorConfiguration_iOS_8_3

- (NSString *)name
{
  return @"iOS 8.3";
}

@end

@implementation FBSimulatorConfiguration_iOS_8_4

- (NSString *)name
{
  return @"iOS 8.4";
}

@end

@implementation FBSimulatorConfiguration_iOS_9_0

- (NSString *)name
{
  return @"iOS 9.0";
}

@end

@implementation FBSimulatorConfiguration_iOS_9_1

- (NSString *)name
{
  return @"iOS 9.1";
}

@end

@implementation FBSimulatorConfiguration_iOS_9_2

- (NSString *)name
{
  return @"iOS 9.2";
}

@end

@implementation FBSimulatorConfiguration_iOS_9_3

- (NSString *)name
{
  return @"iOS 9.3";
}

@end

@implementation FBSimulatorConfiguration_tvOS_Base

- (NSString *)name
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSSet *)families
{
  return [NSSet setWithObject:FBSimulatorConfiguration_Family_TV.new];
}

@end

@implementation FBSimulatorConfiguration_tvOS_9_0

- (NSString *)name
{
  return @"tvOS 9.0";
}

@end

@implementation FBSimulatorConfiguration_tvOS_9_1

- (NSString *)name
{
  return @"tvOS 9.1";
}

@end

@implementation FBSimulatorConfiguration_tvOS_9_2

- (NSString *)name
{
  return @"tvOS 9.2";
}

@end

@implementation FBSimulatorConfiguration_watchOS_Base

- (NSString *)name
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSSet *)families
{
  return [NSSet setWithObject:FBSimulatorConfiguration_Family_Watch.new];
}

@end

@implementation FBSimulatorConfiguration_watchOS_2_0

- (NSString *)name
{
  return @"watchOS 2.0";
}

@end

@implementation FBSimulatorConfiguration_watchOS_2_1

- (NSString *)name
{
  return @"watchOS 2.1";
}

@end

@implementation FBSimulatorConfiguration_watchOS_2_2

- (NSString *)name
{
  return @"watchOS 2.2";
}

@end

@implementation FBSimulatorConfigurationVariants

#pragma mark Lookup Tables

+ (NSArray<id<FBSimulatorConfiguration_Device>> *)deviceConfigurations
{
  static dispatch_once_t onceToken;
  static NSArray<id<FBSimulatorConfiguration_Device>> *deviceConfigurations;
  dispatch_once(&onceToken, ^{
    deviceConfigurations = @[
      FBSimulatorConfiguration_Device_iPhone4s.new,
      FBSimulatorConfiguration_Device_iPhone5.new,
      FBSimulatorConfiguration_Device_iPhone5s.new,
      FBSimulatorConfiguration_Device_iPhone6.new,
      FBSimulatorConfiguration_Device_iPhone6Plus.new,
      FBSimulatorConfiguration_Device_iPhone6S.new,
      FBSimulatorConfiguration_Device_iPhone6SPlus.new,
      FBSimulatorConfiguration_Device_iPad2.new,
      FBSimulatorConfiguration_Device_iPadRetina.new,
      FBSimulatorConfiguration_Device_iPadAir.new,
      FBSimulatorConfiguration_Device_iPadPro.new,
      FBSimulatorConfiguration_Device_iPadAir2.new,
      FBSimulatorConfiguration_Device_AppleWatch38mm.new,
      FBSimulatorConfiguration_Device_AppleWatch42mm.new,
      FBSimulatorConfiguration_Device_AppleTV1080p.new
    ];
  });
  return deviceConfigurations;
}

+ (NSArray<id<FBSimulatorConfiguration_OS>> *)OSConfigurations
{
  static dispatch_once_t onceToken;
  static NSArray<id<FBSimulatorConfiguration_OS>> *OSConfigurations;
  dispatch_once(&onceToken, ^{
    OSConfigurations = @[
      FBSimulatorConfiguration_iOS_7_1.new,
      FBSimulatorConfiguration_iOS_8_0.new,
      FBSimulatorConfiguration_iOS_8_1.new,
      FBSimulatorConfiguration_iOS_8_2.new,
      FBSimulatorConfiguration_iOS_8_3.new,
      FBSimulatorConfiguration_iOS_8_4.new,
      FBSimulatorConfiguration_iOS_9_0.new,
      FBSimulatorConfiguration_iOS_9_1.new,
      FBSimulatorConfiguration_iOS_9_2.new,
      FBSimulatorConfiguration_iOS_9_3.new,
      FBSimulatorConfiguration_tvOS_9_0.new,
      FBSimulatorConfiguration_tvOS_9_1.new,
      FBSimulatorConfiguration_tvOS_9_2.new,
      FBSimulatorConfiguration_watchOS_2_0.new,
      FBSimulatorConfiguration_watchOS_2_1.new,
      FBSimulatorConfiguration_watchOS_2_2.new
    ];
  });
  return OSConfigurations;
}

+ (NSDictionary<NSString *, id<FBSimulatorConfiguration_Device>> *)nameToDevice
{
  static dispatch_once_t onceToken;
  static NSDictionary<NSString *, id<FBSimulatorConfiguration_Device>> *mapping;
  dispatch_once(&onceToken, ^{
    NSArray *instances = self.deviceConfigurations;
    NSMutableDictionary<NSString *, id<FBSimulatorConfiguration_Device>> *dictionary = [NSMutableDictionary dictionary];
    for (id<FBSimulatorConfiguration_Device> device in instances) {
      dictionary[device.deviceName] = device;
    }
    mapping = [dictionary copy];
  });
  return mapping;
}

+ (NSDictionary<NSString *, id<FBSimulatorConfiguration_OS>> *)nameToOSVersion
{
  static dispatch_once_t onceToken;
  static NSDictionary<NSString *, id<FBSimulatorConfiguration_OS>> *mapping;
  dispatch_once(&onceToken, ^{
    NSArray *instances = self.OSConfigurations;
    NSMutableDictionary<NSString *, id<FBSimulatorConfiguration_OS>> *dictionary = [NSMutableDictionary dictionary];
    for (id<FBSimulatorConfiguration_OS> os in instances) {
      dictionary[os.name] = os;
    }
    mapping = [dictionary copy];
  });
  return mapping;
}

@end

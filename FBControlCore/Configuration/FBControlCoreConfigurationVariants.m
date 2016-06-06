/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBControlCoreConfigurationVariants.h"

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

@end

#pragma mark Families

@implementation FBSimulatorConfiguration_Family_iPhone

- (FBControlCoreProductFamily)productFamilyID
{
  return FBControlCoreProductFamilyiPhone;
}

@end

@implementation FBSimulatorConfiguration_Family_iPad

- (FBControlCoreProductFamily)productFamilyID
{
  return FBControlCoreProductFamilyiPad;
}

@end

@implementation FBSimulatorConfiguration_Family_TV

- (FBControlCoreProductFamily)productFamilyID
{
  return FBControlCoreProductFamilyAppleTV;
}

@end

@implementation FBSimulatorConfiguration_Family_Watch

- (FBControlCoreProductFamily)productFamilyID
{
  return FBControlCoreProductFamilyAppleWatch;
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone_Base

- (NSString *)deviceName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSSet<NSString *> *)productTypes
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)deviceArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)simulatorArchitecture
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

@implementation FBControlCoreConfiguration_Device_iPhone4s

- (NSString *)deviceName
{
  return @"iPhone 4s";
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone4,1"]];
}

- (NSString *)deviceArchitecture
{
  return @"armv7";
}

- (NSString *)simulatorArchitecture
{
  return @"i386";
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone5

- (NSString *)deviceName
{
  return @"iPhone 5";
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone5,1", @"iPhone5,2"]];
}

- (NSString *)deviceArchitecture
{
  return @"armv7s";
}

- (NSString *)simulatorArchitecture
{
  return @"i386";
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone5s

- (NSString *)deviceName
{
  return @"iPhone 5s";
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone6,1", @"iPhone6,2"]];
}

- (NSString *)deviceArchitecture
{
  return @"arm64";
}

- (NSString *)simulatorArchitecture
{
  return @"x86_64";
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone6

- (NSString *)deviceName
{
  return @"iPhone 6";
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone7,2"]];
}

- (NSString *)deviceArchitecture
{
  return @"arm64";
}

- (NSString *)simulatorArchitecture
{
  return @"x86_64";
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone6Plus

- (NSString *)deviceName
{
  return @"iPhone 6 Plus";
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone7,1"]];
}

- (NSString *)deviceArchitecture
{
  return @"arm64";
}

- (NSString *)simulatorArchitecture
{
  return @"x86_64";
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone6S

- (NSString *)deviceName
{
  return @"iPhone 6s";
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone8,1"]];
}

- (NSString *)deviceArchitecture
{
  return @"arm64";
}

- (NSString *)simulatorArchitecture
{
  return @"x86_64";
}

@end

@implementation FBControlCoreConfiguration_Device_iPhone6SPlus

- (NSString *)deviceName
{
  return @"iPhone 6s Plus";
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPhone8,2"]];
}

- (NSString *)deviceArchitecture
{
  return @"arm64";
}

- (NSString *)simulatorArchitecture
{
  return @"x86_64";
}

@end

@implementation FBControlCoreConfiguration_Device_iPad_Base

- (NSString *)deviceName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSSet<NSString *> *)productTypes
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)deviceArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)simulatorArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id<FBSimulatorConfiguration_Family>)family
{
  return FBSimulatorConfiguration_Family_iPad.new;
}

@end

@implementation FBControlCoreConfiguration_Device_iPad2

- (NSString *)deviceName
{
  return @"iPad 2";
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPad2,1", @"iPad2,2", @"iPad2,3", @"iPad2,4"]];
}

- (NSString *)deviceArchitecture
{
  return @"armv7";
}

- (NSString *)simulatorArchitecture
{
  return @"i386";
}

@end

@implementation FBControlCoreConfiguration_Device_iPadRetina

- (NSString *)deviceName
{
  return @"iPad Retina";
}

- (NSSet<NSString *> *)productTypes
{
  // Both 'iPad 3' and 'iPad 4'.
  return [NSSet setWithArray:@[@"iPad3,1", @"iPad3,2", @"iPad3,3", @"iPad3,4", @"iPad3,5", @"iPad3,6"]];
}

- (NSString *)deviceArchitecture
{
  return @"armv7";
}

- (NSString *)simulatorArchitecture
{
  return @"i386";
}

@end

@implementation FBControlCoreConfiguration_Device_iPadAir

- (NSString *)deviceName
{
  return @"iPad Air";
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPad4,1", @"iPad4,2", @"iPad4,3"]];
}

- (NSString *)deviceArchitecture
{
  return @"arm64";
}

- (NSString *)simulatorArchitecture
{
  return @"x86_64";
}

@end

@implementation FBControlCoreConfiguration_Device_iPadAir2

- (NSString *)deviceName
{
  return @"iPad Air 2";
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"iPad5,3", @"iPad5,4"]];
}

- (NSString *)deviceArchitecture
{
  return @"arm64";
}

- (NSString *)simulatorArchitecture
{
  return @"x86_64";
}

@end

@implementation FBControlCoreConfiguration_Device_iPadPro

- (NSString *)deviceName
{
  return @"iPad Pro";
}

- (NSSet<NSString *> *)productTypes
{
  // Both the 9" and 12" Variants.
  return [NSSet setWithArray:@[@"iPad6,7", @"iPad6,8", @"iPad6,3", @"iPad6,4"]];
}

- (NSString *)deviceArchitecture
{
  return @"arm64";
}

- (NSString *)simulatorArchitecture
{
  return @"x86_64";
}

@end

@implementation FBControlCoreConfiguration_Device_tvOS_Base

- (NSString *)deviceName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSSet<NSString *> *)productTypes
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)deviceArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)simulatorArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id<FBSimulatorConfiguration_Family>)family
{
  return FBSimulatorConfiguration_Family_TV.new;
}

@end

@implementation FBControlCoreConfiguration_Device_AppleTV1080p

- (NSString *)deviceName
{
  return @"Apple TV 1080p";
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"AppleTV5,3"]];
}

- (NSString *)deviceArchitecture
{
  return @"arm64";
}

- (NSString *)simulatorArchitecture
{
  return @"x86_64";
}

@end

@implementation FBControlCoreConfiguration_Device_watchOS_Base

- (NSString *)deviceName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSSet<NSString *> *)productTypes
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)deviceArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)simulatorArchitecture
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id<FBSimulatorConfiguration_Family>)family
{
  return FBSimulatorConfiguration_Family_Watch.new;
}

@end

@implementation FBControlCoreConfiguration_Device_AppleWatch38mm

- (NSString *)deviceName
{
  return @"Apple Watch - 38mm";
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"Watch1,1"]];
}

- (NSString *)deviceArchitecture
{
  return @"armv7";
}

- (NSString *)simulatorArchitecture
{
  return @"i386";
}

@end

@implementation FBControlCoreConfiguration_Device_AppleWatch42mm

- (NSString *)deviceName
{
  return @"Apple Watch - 42mm";
}

- (NSSet<NSString *> *)productTypes
{
  return [NSSet setWithArray:@[@"Watch1,2"]];
}

- (NSString *)deviceArchitecture
{
  return @"armv7";
}

- (NSString *)simulatorArchitecture
{
  return @"i386";
}

@end

#pragma mark OS Versions

@implementation FBControlCoreConfiguration_iOS_Base

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

@implementation FBControlCoreConfiguration_iOS_7_1

- (NSString *)name
{
  return @"iOS 7.1";
}

@end

@implementation FBControlCoreConfiguration_iOS_8_0

- (NSString *)name
{
  return @"iOS 8.0";
}

@end

@implementation FBControlCoreConfiguration_iOS_8_1

- (NSString *)name
{
  return @"iOS 8.1";
}

@end

@implementation FBControlCoreConfiguration_iOS_8_2

- (NSString *)name
{
  return @"iOS 8.2";
}

@end

@implementation FBControlCoreConfiguration_iOS_8_3

- (NSString *)name
{
  return @"iOS 8.3";
}

@end

@implementation FBControlCoreConfiguration_iOS_8_4

- (NSString *)name
{
  return @"iOS 8.4";
}

@end

@implementation FBControlCoreConfiguration_iOS_9_0

- (NSString *)name
{
  return @"iOS 9.0";
}

@end

@implementation FBControlCoreConfiguration_iOS_9_1

- (NSString *)name
{
  return @"iOS 9.1";
}

@end

@implementation FBControlCoreConfiguration_iOS_9_2

- (NSString *)name
{
  return @"iOS 9.2";
}

@end

@implementation FBControlCoreConfiguration_iOS_9_3

- (NSString *)name
{
  return @"iOS 9.3";
}

@end

@implementation FBControlCoreConfiguration_iOS_9_3_1

- (NSString *)name
{
  return @"iOS 9.3.1";
}

@end

@implementation FBControlCoreConfiguration_iOS_9_3_2

- (NSString *)name
{
  return @"iOS 9.3.2";
}

@end

@implementation FBControlCoreConfiguration_tvOS_Base

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

@implementation FBControlCoreConfiguration_tvOS_9_0

- (NSString *)name
{
  return @"tvOS 9.0";
}

@end

@implementation FBControlCoreConfiguration_tvOS_9_1

- (NSString *)name
{
  return @"tvOS 9.1";
}

@end

@implementation FBControlCoreConfiguration_tvOS_9_2

- (NSString *)name
{
  return @"tvOS 9.2";
}

@end

@implementation FBControlCoreConfiguration_watchOS_Base

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

@implementation FBControlCoreConfiguration_watchOS_2_0

- (NSString *)name
{
  return @"watchOS 2.0";
}

@end

@implementation FBControlCoreConfiguration_watchOS_2_1

- (NSString *)name
{
  return @"watchOS 2.1";
}

@end

@implementation FBControlCoreConfiguration_watchOS_2_2

- (NSString *)name
{
  return @"watchOS 2.2";
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
      FBControlCoreConfiguration_Device_iPad2.new,
      FBControlCoreConfiguration_Device_iPadRetina.new,
      FBControlCoreConfiguration_Device_iPadAir.new,
      FBControlCoreConfiguration_Device_iPadPro.new,
      FBControlCoreConfiguration_Device_iPadAir2.new,
      FBControlCoreConfiguration_Device_AppleWatch38mm.new,
      FBControlCoreConfiguration_Device_AppleWatch42mm.new,
      FBControlCoreConfiguration_Device_AppleTV1080p.new
    ];
  });
  return deviceConfigurations;
}

+ (NSArray<id<FBControlCoreConfiguration_OS>> *)OSConfigurations
{
  static dispatch_once_t onceToken;
  static NSArray<id<FBControlCoreConfiguration_OS>> *OSConfigurations;
  dispatch_once(&onceToken, ^{
    OSConfigurations = @[
      FBControlCoreConfiguration_iOS_7_1.new,
      FBControlCoreConfiguration_iOS_8_0.new,
      FBControlCoreConfiguration_iOS_8_1.new,
      FBControlCoreConfiguration_iOS_8_2.new,
      FBControlCoreConfiguration_iOS_8_3.new,
      FBControlCoreConfiguration_iOS_8_4.new,
      FBControlCoreConfiguration_iOS_9_0.new,
      FBControlCoreConfiguration_iOS_9_1.new,
      FBControlCoreConfiguration_iOS_9_2.new,
      FBControlCoreConfiguration_iOS_9_3.new,
      FBControlCoreConfiguration_iOS_9_3_1.new,
      FBControlCoreConfiguration_iOS_9_3_2.new,
      FBControlCoreConfiguration_tvOS_9_0.new,
      FBControlCoreConfiguration_tvOS_9_1.new,
      FBControlCoreConfiguration_tvOS_9_2.new,
      FBControlCoreConfiguration_watchOS_2_0.new,
      FBControlCoreConfiguration_watchOS_2_1.new,
      FBControlCoreConfiguration_watchOS_2_2.new
    ];
  });
  return OSConfigurations;
}

+ (NSDictionary<NSString *, id<FBControlCoreConfiguration_Device>> *)nameToDevice
{
  static dispatch_once_t onceToken;
  static NSDictionary<NSString *, id<FBControlCoreConfiguration_Device>> *mapping;
  dispatch_once(&onceToken, ^{
    NSArray *instances = self.deviceConfigurations;
    NSMutableDictionary<NSString *, id<FBControlCoreConfiguration_Device>> *dictionary = [NSMutableDictionary dictionary];
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

+ (NSDictionary<NSString *, id<FBControlCoreConfiguration_OS>> *)nameToOSVersion
{
  static dispatch_once_t onceToken;
  static NSDictionary<NSString *, id<FBControlCoreConfiguration_OS>> *mapping;
  dispatch_once(&onceToken, ^{
    NSArray *instances = self.OSConfigurations;
    NSMutableDictionary<NSString *, id<FBControlCoreConfiguration_OS>> *dictionary = [NSMutableDictionary dictionary];
    for (id<FBControlCoreConfiguration_OS> os in instances) {
      dictionary[os.name] = os;
    }
    mapping = [dictionary copy];
  });
  return mapping;
}

+ (NSDictionary<NSString *, NSSet<NSString *> *> *)baseArchToCompatibleArch
{
  return @{
    @"arm64" : [NSSet setWithArray:@[@"arm64", @"armv7s", @"armv7"]],
    @"armv7s" : [NSSet setWithArray:@[@"armv7s", @"armv7"]],
    @"armv7" : [NSSet setWithArray:@[@"armv7"]],
    @"i386" : [NSSet setWithObject:@"i386"],
    @"x86_64" : [NSSet setWithArray:@[@"x86_64", @"i386"]],
  };
}

@end

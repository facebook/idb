/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorConfiguration.h"
#import "FBSimulatorConfiguration+Private.h"

#import <objc/runtime.h>

#import <FBControlCore/FBControlCoreGlobalConfiguration.h>

#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorControl+PrincipalClass.h"

@implementation FBSimulatorConfigurationVariant_Base

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
  self = [super init];
  if (!self) {
    return nil;
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
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

@implementation FBSimulatorConfiguration

+ (void)initialize
{
  [FBSimulatorControl loadPrivateFrameworksOrAbort];
}

#pragma mark Initializers

- (instancetype)initWithNamedDevice:(id<FBSimulatorConfiguration_Device>)device os:(id<FBSimulatorConfiguration_OS>)os auxillaryDirectory:(NSString *)auxillaryDirectory
{
  NSParameterAssert(device);
  NSParameterAssert(os);

  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _os = os;
  _auxillaryDirectory = auxillaryDirectory;

  return self;
}

+ (instancetype)defaultConfiguration
{
  static dispatch_once_t onceToken;
  static FBSimulatorConfiguration *configuration;
  dispatch_once(&onceToken, ^{
    id<FBSimulatorConfiguration_Device> device = FBSimulatorConfiguration_Device_iPhone5.new;
    id<FBSimulatorConfiguration_OS> os = [FBSimulatorConfiguration newestAvailableOSForDevice:device];
    configuration = [[FBSimulatorConfiguration alloc] initWithNamedDevice:device os:os auxillaryDirectory:nil];
  });
  return configuration;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc]
    initWithNamedDevice:self.device
    os:self.os
    auxillaryDirectory:self.auxillaryDirectory];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  id<FBSimulatorConfiguration_Device> device = [coder decodeObjectForKey:NSStringFromSelector(@selector(device))];
  id<FBSimulatorConfiguration_OS> os = [coder decodeObjectForKey:NSStringFromSelector(@selector(os))];
  NSString *auxillaryDirectory = [coder decodeObjectForKey:NSStringFromSelector(@selector(auxillaryDirectory))];
  return [self initWithNamedDevice:device os:os auxillaryDirectory:auxillaryDirectory];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.device forKey:NSStringFromSelector(@selector(device))];
  [coder encodeObject:self.os forKey:NSStringFromSelector(@selector(os))];
  [coder encodeObject:self.auxillaryDirectory forKey:NSStringFromSelector(@selector(auxillaryDirectory))];
}

#pragma mark Accessors

- (NSString *)deviceName
{
  return self.device.deviceName;
}

- (NSString *)osVersionString
{
  return self.os.name;
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.deviceName.hash ^ self.osVersionString.hash ^ self.auxillaryDirectory.hash;
}

- (BOOL)isEqual:(FBSimulatorConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }

  return [self.deviceName isEqualToString:object.deviceName] &&
         [self.osVersionString isEqualToString:object.osVersionString] &&
         (self.auxillaryDirectory == object.auxillaryDirectory || [self.auxillaryDirectory isEqualToString:object.auxillaryDirectory]);
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Device '%@' | OS Version '%@' | Aux Directory %@",
    self.deviceName,
    self.osVersionString,
    self.auxillaryDirectory
  ];
}

- (NSString *)shortDescription
{
  return [self description];
}

- (NSString *)debugDescription
{
  return [self description];
}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  return @{
    @"device" : self.deviceName,
    @"os" : self.osVersionString,
    @"aux_directory" : self.auxillaryDirectory ?: NSNull.null
  };
}

#pragma mark Devices

+ (instancetype)iPhone4s
{
  return [self.defaultConfiguration iPhone4s];
}

- (instancetype)iPhone4s
{
  return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_iPhone4s.class];
}

+ (instancetype)iPhone5
{
  return [self.defaultConfiguration iPhone5];
}

- (instancetype)iPhone5
{
  return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_iPhone5.class];
}

+ (instancetype)iPhone5s
{
  return [self.defaultConfiguration iPhone5s];
}

- (instancetype)iPhone5s
{
  return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_iPhone5s.class];
}

+ (instancetype)iPhone6
{
  return [self.defaultConfiguration iPhone6];
}

- (instancetype)iPhone6
{
  return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_iPhone6.class];
}

+ (instancetype)iPhone6s
{
    return [self.defaultConfiguration iPhone6s];
}

- (instancetype)iPhone6s
{
    return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_iPhone6S.class];
}

+ (instancetype)iPhone6Plus
{
  return [self.defaultConfiguration iPhone6Plus];
}

- (instancetype)iPhone6Plus
{
  return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_iPhone6Plus.class];
}

+ (instancetype)iPhone6sPlus
{
    return [self.defaultConfiguration iPhone6sPlus];
}

- (instancetype)iPhone6sPlus
{
    return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_iPhone6SPlus.class];
}

+ (instancetype)iPad2
{
  return [self.defaultConfiguration iPad2];
}

- (instancetype)iPad2
{
  return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_iPad2.class];
}

+ (instancetype)iPadRetina
{
  return [self.defaultConfiguration iPadRetina];
}

- (instancetype)iPadRetina
{
  return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_iPadRetina.class];
}

+ (instancetype)iPadPro
{
    return [self.defaultConfiguration iPadPro];
}

- (instancetype)iPadPro
{
    return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_iPadPro.class];
}

+ (instancetype)iPadAir
{
  return [self.defaultConfiguration iPadAir];
}

- (instancetype)iPadAir
{
  return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_iPadAir.class];
}

+ (instancetype)iPadAir2
{
  return [self.defaultConfiguration iPadAir2];
}

- (instancetype)iPadAir2
{
  return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_iPadAir2.class];
}

+ (instancetype)watch38mm
{
  return [self.defaultConfiguration watch38mm];
}

- (instancetype)watch38mm
{
  return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_AppleWatch38mm.class];
}

+ (instancetype)watch42mm
{
  return [self.defaultConfiguration watch42mm];
}

- (instancetype)watch42mm
{
  return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_AppleWatch42mm.class];
}

+ (instancetype)appleTV1080p
{
  return [self.defaultConfiguration appleTV1080p];
}

- (instancetype)appleTV1080p
{
  return [self updateNamedDeviceClass:FBSimulatorConfiguration_Device_AppleTV1080p.class];
}

+ (instancetype)withDeviceNamed:(NSString *)deviceName
{
  return [self.defaultConfiguration withDeviceNamed:deviceName];
}

- (instancetype)withDeviceNamed:(NSString *)deviceName
{
  return [self updateNamedDevice:self.class.nameToDevice[deviceName]];
}

#pragma mark OS Versions

- (instancetype)iOS_7_1
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_iOS_7_1.class];
}

- (instancetype)iOS_8_0
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_iOS_8_0.class];
}

- (instancetype)iOS_8_1
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_iOS_8_1.class];
}

- (instancetype)iOS_8_2
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_iOS_8_2.class];
}

- (instancetype)iOS_8_3
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_iOS_8_3.class];
}

- (instancetype)iOS_8_4
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_iOS_8_4.class];
}

- (instancetype)iOS_9_0
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_iOS_9_0.class];
}

- (instancetype)iOS_9_1
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_iOS_9_1.class];
}

- (instancetype)iOS_9_2
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_iOS_9_2.class];
}

- (instancetype)iOS_9_3
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_iOS_9_3.class];
}

- (instancetype)tvOS_9_0
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_tvOS_9_0.class];
}

- (instancetype)tvOS_9_1
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_tvOS_9_1.class];
}

- (instancetype)tvOS_9_2
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_tvOS_9_2.class];
}

- (instancetype)watchOS_2_0
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_watchOS_2_0.class];
}

- (instancetype)watchOS_2_1
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_watchOS_2_1.class];
}

- (instancetype)watchOS_2_2
{
  return [self updateOSVersionClass:FBSimulatorConfiguration_watchOS_2_2.class];
}

+ (instancetype)withOSNamed:(NSString *)osName
{
  return [self.defaultConfiguration withOSNamed:osName];
}

- (instancetype)withOSNamed:(NSString *)osName
{
  return [self updateOSVersion:self.class.nameToOSVersion[osName]];
}

#pragma mark Auxillary Directory

- (instancetype)withAuxillaryDirectory:(NSString *)auxillaryDirectory
{
  FBSimulatorConfiguration *configuration = [self copy];
  configuration.auxillaryDirectory = auxillaryDirectory;
  return configuration;
}

#pragma mark Private

#pragma mark Deriving new Configurations

- (instancetype)updateNamedDeviceClass:(Class)class
{
  return [self updateNamedDevice:[class new]];
}

- (instancetype)updateNamedDevice:(id<FBSimulatorConfiguration_Device>)device
{
  if (!device) {
    return nil;
  }
  FBSimulatorConfiguration *configuration = [self copy];
  configuration.device = device;
  if (![FBSimulatorConfiguration device:device andOSPairSupported:configuration.os]) {
    configuration.os = [FBSimulatorConfiguration newestAvailableOSForDevice:device];
  }
  return configuration;
}

- (instancetype)updateOSVersionClass:(Class)class
{
  return [self updateOSVersion:[class new]];
}

- (instancetype)updateOSVersion:(id<FBSimulatorConfiguration_OS>)os
{
  if (!os) {
    return nil;
  }
  FBSimulatorConfiguration *configuration = [self copy];
  configuration.os = os;
  return configuration;
}


+ (BOOL)device:(id<FBSimulatorConfiguration_Device>)device andOSPairSupported:(id<FBSimulatorConfiguration_OS>)os
{
  return [os.families containsObject:device.family];
}

#pragma mark Lookup Tables

+ (NSArray *)deviceConfigurations
{
  static dispatch_once_t onceToken;
  static NSArray *deviceConfigurations;
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

+ (NSArray *)OSConfigurations
{
  static dispatch_once_t onceToken;
  static NSArray *OSConfigurations;
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

+ (NSDictionary *)nameToDevice
{
  static dispatch_once_t onceToken;
  static NSDictionary *mapping;
  dispatch_once(&onceToken, ^{
    NSArray *instances = self.deviceConfigurations;
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    for (id<FBSimulatorConfiguration_Device> device in instances) {
      dictionary[device.deviceName] = device;
    }
    mapping = [dictionary copy];
  });
  return mapping;
}

+ (NSDictionary *)nameToOSVersion
{
  static dispatch_once_t onceToken;
  static NSDictionary *mapping;
  dispatch_once(&onceToken, ^{
    NSArray *instances = self.OSConfigurations;
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    for (id<FBSimulatorConfiguration_OS> os in instances) {
      dictionary[os.name] = os;
    }
    mapping = [dictionary copy];
  });
  return mapping;
}

@end

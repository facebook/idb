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

#import "FBSimulatorControlStaticConfiguration.h"

@implementation FBSimulatorConfigurationVariant_Base

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
  
}

@end

@implementation FBSimulatorConfigurationNamedDevice_iPhone4s

- (NSString *)deviceName
{
  return @"iPhone 4s";
}

@end

@implementation FBSimulatorConfigurationNamedDevice_iPhone5

- (NSString *)deviceName
{
  return @"iPhone 5";
}

@end

@implementation FBSimulatorConfigurationNamedDevice_iPhone5s

- (NSString *)deviceName
{
  return @"iPhone 5s";
}

@end

@implementation FBSimulatorConfigurationNamedDevice_iPhone6

- (NSString *)deviceName
{
  return @"iPhone 6";
}

@end

@implementation FBSimulatorConfigurationNamedDevice_iPhone6Plus

- (NSString *)deviceName
{
  return @"iPhone 6 Plus";
}

@end

@implementation FBSimulatorConfigurationNamedDevice_iPhone6S

- (NSString *)deviceName
{
  return @"iPhone 6s";
}

@end

@implementation FBSimulatorConfigurationNamedDevice_iPhone6SPlus

- (NSString *)deviceName
{
  return @"iPhone 6s Plus";
}

@end

@implementation FBSimulatorConfigurationNamedDevice_iPad2

- (NSString *)deviceName
{
  return @"iPad 2";
}

@end

@implementation FBSimulatorConfigurationNamedDevice_iPadRetina

- (NSString *)deviceName
{
  return @"iPad Retina";
}

@end

@implementation FBSimulatorConfigurationNamedDevice_iPadAir

- (NSString *)deviceName
{
  return @"iPad Air";
}

@end

@implementation FBSimulatorConfigurationNamedDevice_iPadAir2

- (NSString *)deviceName
{
  return @"iPad Air 2";
}

@end

@implementation FBSimulatorConfigurationNamedDevice_iPadPro

- (NSString *)deviceName
{
  return @"iPad Pro";
}

@end

@implementation FBSimulatorConfigurationOSVersion_7_1

- (NSString *)osVersion
{
  return @"7.1";
}

@end

@implementation FBSimulatorConfigurationOSVersion_8_0

- (NSString *)osVersion
{
  return @"8.0";
}

@end

@implementation FBSimulatorConfigurationOSVersion_8_1

- (NSString *)osVersion
{
  return @"8.1";
}

@end

@implementation FBSimulatorConfigurationOSVersion_8_2

- (NSString *)osVersion
{
  return @"8.2";
}

@end

@implementation FBSimulatorConfigurationOSVersion_8_3

- (NSString *)osVersion
{
  return @"8.3";
}

@end

@implementation FBSimulatorConfigurationOSVersion_8_4

- (NSString *)osVersion
{
  return @"8.4";
}

@end

@implementation FBSimulatorConfigurationOSVersion_9_0

- (NSString *)osVersion
{
  return @"9.0";
}

@end

@implementation FBSimulatorConfigurationOSVersion_9_1

- (NSString *)osVersion
{
  return @"9.1";
}

@end

@implementation FBSimulatorConfigurationOSVersion_9_2

- (NSString *)osVersion
{
  return @"9.2";
}

@end

@implementation FBSimulatorConfigurationScale_25

- (NSString *)scaleString
{
  return @"0.25";
}

@end

@implementation FBSimulatorConfigurationScale_50

- (NSString *)scaleString
{
  return @"0.50";
}

@end

@implementation FBSimulatorConfigurationScale_75

- (NSString *)scaleString
{
  return @"0.75";
}

@end

@implementation FBSimulatorConfigurationScale_100

- (NSString *)scaleString
{
  return @"1.00";
}

@end

@implementation FBSimulatorConfiguration

#pragma mark Initializers

- (instancetype)initWithNamedDevice:(id<FBSimulatorConfigurationNamedDevice>)namedDevice osVersion:(id<FBSimulatorConfigurationOSVersion>)osVersion locale:(NSLocale *)locale scale:(id<FBSimulatorConfigurationScale>)scale
{
  NSParameterAssert(namedDevice);
  NSParameterAssert(osVersion);
  NSParameterAssert(scale);

  self = [super init];
  if (!self) {
    return nil;
  }

  _namedDevice = namedDevice;
  _osVersion = osVersion;
  _locale = locale;
  _scale = scale;

  return self;
}

+ (instancetype)defaultConfiguration
{
  static dispatch_once_t onceToken;
  static FBSimulatorConfiguration *configuration;
  dispatch_once(&onceToken, ^{
    configuration = [FBSimulatorConfiguration new];
    configuration.namedDevice = [FBSimulatorConfigurationNamedDevice_iPhone5 new];
    configuration.osVersion = [FBSimulatorConfiguration defaultOSVersion];
    configuration.scale = [FBSimulatorConfigurationScale_50 new];
  });
  return configuration;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc]
    initWithNamedDevice:self.namedDevice
    osVersion:self.osVersion
    locale:self.locale
    scale:self.scale];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _namedDevice = [coder decodeObjectForKey:NSStringFromSelector(@selector(namedDevice))];
  _osVersion = [coder decodeObjectForKey:NSStringFromSelector(@selector(osVersion))];
  _locale = [coder decodeObjectForKey:NSStringFromSelector(@selector(locale))];
  _scale = [coder decodeObjectForKey:NSStringFromSelector(@selector(scale))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.namedDevice forKey:NSStringFromSelector(@selector(namedDevice))];
  [coder encodeObject:self.osVersion forKey:NSStringFromSelector(@selector(osVersion))];
  [coder encodeObject:self.locale forKey:NSStringFromSelector(@selector(locale))];
  [coder encodeObject:self.scale forKey:NSStringFromSelector(@selector(scale))];
}

#pragma mark Accessors

- (NSString *)deviceName
{
  return self.namedDevice.deviceName;
}

- (NSString *)osVersionString
{
  return self.osVersion.osVersion;
}

- (NSString *)scaleString
{
  return self.scale.scaleString;
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.deviceName.hash | self.osVersionString.hash | self.locale.hash | self.scaleString.hash;
}

- (BOOL)isEqual:(FBSimulatorConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }

  return [self.deviceName isEqualToString:object.deviceName] &&
         [self.osVersionString isEqualToString:object.osVersionString] &&
         [self.scaleString isEqualToString:object.scaleString] &&
         ((self.locale == nil && object.locale == nil) || [self.locale isEqual:object.locale]);
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Simulator '%@' | OS Version '%@' | Locale '%@' | Scale '%@'",
    self.deviceName,
    self.osVersionString,
    self.locale,
    self.scaleString
  ];
}

#pragma mark Mutators

+ (instancetype)iPhone4s
{
  return [self.defaultConfiguration iPhone4s];
}

- (instancetype)iPhone4s
{
  return [self updateNamedDeviceClass:FBSimulatorConfigurationNamedDevice_iPhone4s.class];
}

+ (instancetype)iPhone5
{
  return [self.defaultConfiguration iPhone5];
}

- (instancetype)iPhone5
{
  return [self updateNamedDeviceClass:FBSimulatorConfigurationNamedDevice_iPhone5.class];
}

+ (instancetype)iPhone5s
{
  return [self.defaultConfiguration iPhone5s];
}

- (instancetype)iPhone5s
{
  return [self updateNamedDeviceClass:FBSimulatorConfigurationNamedDevice_iPhone5s.class];
}

+ (instancetype)iPhone6
{
  return [self.defaultConfiguration iPhone6];
}

- (instancetype)iPhone6
{
  return [self updateNamedDeviceClass:FBSimulatorConfigurationNamedDevice_iPhone6.class];
}

+ (instancetype)iPhone6Plus
{
  return [self.defaultConfiguration iPhone6Plus];
}

- (instancetype)iPhone6Plus
{
  return [self updateNamedDeviceClass:FBSimulatorConfigurationNamedDevice_iPhone6Plus.class];
}

+ (instancetype)iPad2
{
  return [self.defaultConfiguration iPad2];
}

- (instancetype)iPad2
{
  return [self updateNamedDeviceClass:FBSimulatorConfigurationNamedDevice_iPad2.class];
}

+ (instancetype)iPadRetina
{
  return [self.defaultConfiguration iPadRetina];
}

- (instancetype)iPadRetina
{
  return [self updateNamedDeviceClass:FBSimulatorConfigurationNamedDevice_iPadRetina.class];
}

+ (instancetype)iPadAir
{
  return [self.defaultConfiguration iPadAir];
}

- (instancetype)iPadAir
{
  return [self updateNamedDeviceClass:FBSimulatorConfigurationNamedDevice_iPadAir.class];
}

+ (instancetype)iPadAir2
{
  return [self.defaultConfiguration iPadAir2];
}

- (instancetype)iPadAir2
{
  return [self updateNamedDeviceClass:FBSimulatorConfigurationNamedDevice_iPadAir2.class];
}

+ (instancetype)named:(NSString *)deviceType
{
  return [self.defaultConfiguration named:deviceType];
}

- (instancetype)named:(NSString *)deviceType
{
  return [self updateNamedDevice:self.class.nameToDevice[deviceType]];
}

- (instancetype)iOS_7_1
{
  return [self updateOSVersionClass:FBSimulatorConfigurationOSVersion_7_1.class];
}

- (instancetype)iOS_8_0
{
  return [self updateOSVersionClass:FBSimulatorConfigurationOSVersion_8_0.class];
}

- (instancetype)iOS_8_1
{
  return [self updateOSVersionClass:FBSimulatorConfigurationOSVersion_8_1.class];
}

- (instancetype)iOS_8_2
{
  return [self updateOSVersionClass:FBSimulatorConfigurationOSVersion_8_2.class];
}

- (instancetype)iOS_8_3
{
  return [self updateOSVersionClass:FBSimulatorConfigurationOSVersion_8_3.class];
}

- (instancetype)iOS_8_4
{
  return [self updateOSVersionClass:FBSimulatorConfigurationOSVersion_8_4.class];
}

- (instancetype)iOS_9_0
{
  return [self updateOSVersionClass:FBSimulatorConfigurationOSVersion_9_0.class];
}

+ (instancetype)iOS:(NSString *)version
{
  return [self.defaultConfiguration iOS:version];
}

- (instancetype)iOS:(NSString *)version
{
  return [self updateOSVersion:self.class.nameToOSVersion[version]];
}

#pragma mark Scale

- (instancetype)scale25Percent
{
  return [self updateScale:[FBSimulatorConfigurationScale_25 new]];
}

- (instancetype)scale50Percent
{
  return [self updateScale:[FBSimulatorConfigurationScale_50 new]];
}

- (instancetype)scale75Percent
{
  return [self updateScale:[FBSimulatorConfigurationScale_75 new]];
}

- (instancetype)scale100Percent
{
  return [self updateScale:[FBSimulatorConfigurationScale_100 new]];
}

- (instancetype)withLocale:(NSLocale *)locale
{
  FBSimulatorConfiguration *configuration = [self copy];
  configuration.locale = locale;
  return configuration;
}

- (instancetype)withLocaleNamed:(NSString *)localeIdentifier
{
  return [self withLocale:[NSLocale localeWithLocaleIdentifier:localeIdentifier]];
}

#pragma mark Private

+ (NSDictionary *)nameToDevice
{
  static dispatch_once_t onceToken;
  static NSDictionary *mapping;
  dispatch_once(&onceToken, ^{
    NSArray *instances = @[
     FBSimulatorConfigurationNamedDevice_iPhone4s.new,
     FBSimulatorConfigurationNamedDevice_iPhone5.new,
     FBSimulatorConfigurationNamedDevice_iPhone5s.new,
     FBSimulatorConfigurationNamedDevice_iPhone6.new,
     FBSimulatorConfigurationNamedDevice_iPhone6Plus.new,
     FBSimulatorConfigurationNamedDevice_iPhone6S.new,
     FBSimulatorConfigurationNamedDevice_iPhone6SPlus.new,
     FBSimulatorConfigurationNamedDevice_iPad2.new,
     FBSimulatorConfigurationNamedDevice_iPadRetina.new,
     FBSimulatorConfigurationNamedDevice_iPadAir.new,
     FBSimulatorConfigurationNamedDevice_iPadAir2.new
    ];

    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    for (id<FBSimulatorConfigurationNamedDevice> device in instances) {
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
    NSArray *instances = @[
      FBSimulatorConfigurationOSVersion_7_1.new,
      FBSimulatorConfigurationOSVersion_8_0.new,
      FBSimulatorConfigurationOSVersion_8_1.new,
      FBSimulatorConfigurationOSVersion_8_2.new,
      FBSimulatorConfigurationOSVersion_8_3.new,
      FBSimulatorConfigurationOSVersion_8_4.new,
      FBSimulatorConfigurationOSVersion_9_0.new,
      FBSimulatorConfigurationOSVersion_9_1.new,
      FBSimulatorConfigurationOSVersion_9_2.new,
    ];

    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    for (id<FBSimulatorConfigurationOSVersion> osVersion in instances) {
      dictionary[osVersion.osVersion] = osVersion;
    }
    mapping = [dictionary copy];
  });
  return mapping;
}

+ (id<FBSimulatorConfigurationOSVersion>)defaultOSVersion
{
  static dispatch_once_t onceToken;
  static id<FBSimulatorConfigurationOSVersion> osVersion;
  dispatch_once(&onceToken, ^{
    NSString *sdkVersion = FBSimulatorControlStaticConfiguration.sdkVersion;
    osVersion = self.class.nameToOSVersion[sdkVersion];
    if (osVersion) {
      return;
    }
    NSString *latestName = [[self.class.nameToOSVersion.allKeys sortedArrayUsingSelector:@selector(compare:)] lastObject];
    osVersion = self.class.nameToOSVersion[latestName];
  });
  return osVersion;
}

- (instancetype)updateNamedDeviceClass:(Class)class
{
  return [self updateNamedDevice:[class new]];
}

- (instancetype)updateNamedDevice:(id<FBSimulatorConfigurationNamedDevice>)namedDevice
{
  if (!namedDevice) {
    return nil;
  }
  FBSimulatorConfiguration *configuration = [self copy];
  configuration.namedDevice = namedDevice;
  return configuration;
}

- (instancetype)updateOSVersionClass:(Class)class
{
  return [self updateOSVersion:[class new]];
}

- (instancetype)updateOSVersion:(id<FBSimulatorConfigurationOSVersion>)osVersion
{
  if (!osVersion) {
    return nil;
  }
  FBSimulatorConfiguration *configuration = [self copy];
  configuration.osVersion = osVersion;
  return configuration;
}

- (instancetype)updateScale:(id<FBSimulatorConfigurationScale>)scale
{
  if (!scale) {
    return nil;
  }
  FBSimulatorConfiguration *configuration = [self copy];
  configuration.scale = scale;
  return configuration;
}

@end

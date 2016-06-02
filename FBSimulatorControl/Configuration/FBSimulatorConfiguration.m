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

@implementation FBSimulatorConfiguration

+ (void)initialize
{
  [FBSimulatorControl loadPrivateFrameworksOrAbort];
}

#pragma mark Initializers

- (instancetype)initWithNamedDevice:(id<FBControlCoreConfiguration_Device>)device os:(id<FBControlCoreConfiguration_OS>)os auxillaryDirectory:(NSString *)auxillaryDirectory
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
    id<FBControlCoreConfiguration_Device> device = FBControlCoreConfiguration_Device_iPhone5.new;
    id<FBControlCoreConfiguration_OS> os = [FBSimulatorConfiguration newestAvailableOSForDevice:device];
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
  id<FBControlCoreConfiguration_Device> device = [coder decodeObjectForKey:NSStringFromSelector(@selector(device))];
  id<FBControlCoreConfiguration_OS> os = [coder decodeObjectForKey:NSStringFromSelector(@selector(os))];
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
  return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_iPhone4s.class];
}

+ (instancetype)iPhone5
{
  return [self.defaultConfiguration iPhone5];
}

- (instancetype)iPhone5
{
  return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_iPhone5.class];
}

+ (instancetype)iPhone5s
{
  return [self.defaultConfiguration iPhone5s];
}

- (instancetype)iPhone5s
{
  return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_iPhone5s.class];
}

+ (instancetype)iPhone6
{
  return [self.defaultConfiguration iPhone6];
}

- (instancetype)iPhone6
{
  return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_iPhone6.class];
}

+ (instancetype)iPhone6s
{
    return [self.defaultConfiguration iPhone6s];
}

- (instancetype)iPhone6s
{
    return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_iPhone6S.class];
}

+ (instancetype)iPhone6Plus
{
  return [self.defaultConfiguration iPhone6Plus];
}

- (instancetype)iPhone6Plus
{
  return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_iPhone6Plus.class];
}

+ (instancetype)iPhone6sPlus
{
    return [self.defaultConfiguration iPhone6sPlus];
}

- (instancetype)iPhone6sPlus
{
    return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_iPhone6SPlus.class];
}

+ (instancetype)iPad2
{
  return [self.defaultConfiguration iPad2];
}

- (instancetype)iPad2
{
  return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_iPad2.class];
}

+ (instancetype)iPadRetina
{
  return [self.defaultConfiguration iPadRetina];
}

- (instancetype)iPadRetina
{
  return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_iPadRetina.class];
}

+ (instancetype)iPadPro
{
    return [self.defaultConfiguration iPadPro];
}

- (instancetype)iPadPro
{
    return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_iPadPro.class];
}

+ (instancetype)iPadAir
{
  return [self.defaultConfiguration iPadAir];
}

- (instancetype)iPadAir
{
  return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_iPadAir.class];
}

+ (instancetype)iPadAir2
{
  return [self.defaultConfiguration iPadAir2];
}

- (instancetype)iPadAir2
{
  return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_iPadAir2.class];
}

+ (instancetype)watch38mm
{
  return [self.defaultConfiguration watch38mm];
}

- (instancetype)watch38mm
{
  return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_AppleWatch38mm.class];
}

+ (instancetype)watch42mm
{
  return [self.defaultConfiguration watch42mm];
}

- (instancetype)watch42mm
{
  return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_AppleWatch42mm.class];
}

+ (instancetype)appleTV1080p
{
  return [self.defaultConfiguration appleTV1080p];
}

- (instancetype)appleTV1080p
{
  return [self updateNamedDeviceClass:FBControlCoreConfiguration_Device_AppleTV1080p.class];
}

+ (instancetype)withDeviceNamed:(NSString *)deviceName
{
  return [self.defaultConfiguration withDeviceNamed:deviceName];
}

- (instancetype)withDeviceNamed:(NSString *)deviceName
{
  return [self updateNamedDevice:FBControlCoreConfigurationVariants.nameToDevice[deviceName]];
}

#pragma mark OS Versions

- (instancetype)iOS_7_1
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_iOS_7_1.class];
}

- (instancetype)iOS_8_0
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_iOS_8_0.class];
}

- (instancetype)iOS_8_1
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_iOS_8_1.class];
}

- (instancetype)iOS_8_2
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_iOS_8_2.class];
}

- (instancetype)iOS_8_3
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_iOS_8_3.class];
}

- (instancetype)iOS_8_4
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_iOS_8_4.class];
}

- (instancetype)iOS_9_0
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_iOS_9_0.class];
}

- (instancetype)iOS_9_1
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_iOS_9_1.class];
}

- (instancetype)iOS_9_2
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_iOS_9_2.class];
}

- (instancetype)iOS_9_3
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_iOS_9_3.class];
}

- (instancetype)tvOS_9_0
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_tvOS_9_0.class];
}

- (instancetype)tvOS_9_1
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_tvOS_9_1.class];
}

- (instancetype)tvOS_9_2
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_tvOS_9_2.class];
}

- (instancetype)watchOS_2_0
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_watchOS_2_0.class];
}

- (instancetype)watchOS_2_1
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_watchOS_2_1.class];
}

- (instancetype)watchOS_2_2
{
  return [self updateOSVersionClass:FBControlCoreConfiguration_watchOS_2_2.class];
}

+ (instancetype)withOSNamed:(NSString *)osName
{
  return [self.defaultConfiguration withOSNamed:osName];
}

- (instancetype)withOSNamed:(NSString *)osName
{
  return [self updateOSVersion:FBControlCoreConfigurationVariants.nameToOSVersion[osName]];
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

- (instancetype)updateNamedDevice:(id<FBControlCoreConfiguration_Device>)device
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

- (instancetype)updateOSVersion:(id<FBControlCoreConfiguration_OS>)os
{
  if (!os) {
    return nil;
  }
  FBSimulatorConfiguration *configuration = [self copy];
  configuration.os = os;
  return configuration;
}

+ (BOOL)device:(id<FBControlCoreConfiguration_Device>)device andOSPairSupported:(id<FBControlCoreConfiguration_OS>)os
{
  return [os.families containsObject:device.family];
}

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorConfiguration.h"

#import <objc/runtime.h>

#import <FBControlCore/FBControlCoreGlobalConfiguration.h>

#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorControl+PrincipalClass.h"
#import "FBSimulatorControlFrameworkLoader.h"

@implementation FBSimulatorConfiguration

+ (void)initialize
{
  [FBSimulatorControlFrameworkLoader loadPrivateFrameworksOrAbort];
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
    configuration = [self makeDefaultConfiguration];
  });
  return configuration;
}

+ (instancetype)makeDefaultConfiguration
{
  id<FBControlCoreConfiguration_Device> device = FBControlCoreConfiguration_Device_iPhone6.new;
  id<FBControlCoreConfiguration_OS> os = [FBSimulatorConfiguration newestAvailableOSForDevice:device];
  NSAssert(
    os,
    @"Could not obtain OS for Default Device '%@'. Available OS Versions %@",
    device,
    [FBCollectionInformation oneLineDescriptionFromArray:[FBSimulatorConfiguration supportedOSVersionsForDevice:device]]
  );
  return [[FBSimulatorConfiguration alloc] initWithNamedDevice:device os:os auxillaryDirectory:nil];
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

- (FBDeviceName)deviceName
{
  return self.device.deviceName;
}

- (NSString *)osVersionString
{
  return self.os.name;
}

- (FBArchitecture)architecture
{
  return self.device.simulatorArchitecture;
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
    @"Device '%@' | OS Version '%@' | Aux Directory %@ | Architecture '%@'",
    self.deviceName,
    self.osVersionString,
    self.auxillaryDirectory,
    self.architecture
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
    @"aux_directory" : self.auxillaryDirectory ?: NSNull.null,
    @"architecture" : self.architecture
  };
}

#pragma mark - Devices

+ (instancetype)withDevice:(id<FBControlCoreConfiguration_Device>)device
{
  return [self.defaultConfiguration withDevice:device];
}

- (instancetype)withDevice:(id<FBControlCoreConfiguration_Device>)device
{
  NSParameterAssert(device);
  return [[FBSimulatorConfiguration alloc] initWithNamedDevice:device os:self.os auxillaryDirectory:self.auxillaryDirectory];
}

+ (instancetype)withDeviceNamed:(FBDeviceName)deviceName
{
  return [self.defaultConfiguration withDeviceNamed:deviceName];
}

- (instancetype)withDeviceNamed:(FBDeviceName)deviceName
{
  id<FBControlCoreConfiguration_Device> device = FBControlCoreConfigurationVariants.nameToDevice[deviceName];
  NSAssert(device, @"%@ is not a valid device name", deviceName);
  return [self withDevice:device];
}

#pragma mark - OS Versions

+ (instancetype)withOS:(id<FBControlCoreConfiguration_OS>)os
{
  return [self.defaultConfiguration withOS:os];
}

- (instancetype)withOS:(id<FBControlCoreConfiguration_OS>)os
{
  NSParameterAssert(os);
  return [[FBSimulatorConfiguration alloc] initWithNamedDevice:self.device os:os auxillaryDirectory:self.auxillaryDirectory];
}

+ (instancetype)withOSNamed:(FBOSVersionName)osName
{
  return [self.defaultConfiguration withOSNamed:osName];
}

- (instancetype)withOSNamed:(FBOSVersionName)osName
{
  id<FBControlCoreConfiguration_OS> os = FBControlCoreConfigurationVariants.nameToOSVersion[osName];
  NSAssert(os, @"%@ is not a valid os name", osName);
  return [self withOS:os];
}

#pragma mark Auxillary Directory

- (instancetype)withAuxillaryDirectory:(NSString *)auxillaryDirectory
{
  return [[FBSimulatorConfiguration alloc] initWithNamedDevice:self.device os:self.os auxillaryDirectory:self.auxillaryDirectory];
}

#pragma mark Private

#pragma mark Deriving new Configurations

- (instancetype)withDevice:(id<FBControlCoreConfiguration_Device>)device andOS:(id<FBControlCoreConfiguration_OS>)os
{
  NSParameterAssert(device);
  NSParameterAssert(os);
  return [[FBSimulatorConfiguration alloc] initWithNamedDevice:device os:os auxillaryDirectory:self.auxillaryDirectory];
}

- (instancetype)updateNamedDeviceClass:(Class)class
{
  id<FBControlCoreConfiguration_Device> device = [class new];
  if ([FBSimulatorConfiguration device:device andOSPairSupported:self.os]) {
    return [self withDevice:device];
  }
  id<FBControlCoreConfiguration_OS> os = [FBSimulatorConfiguration newestAvailableOSForDevice:device];
  return [self withDevice:device andOS:os];
}

- (instancetype)updateOSVersionClass:(Class)class
{
  return [self withOS:[class new]];
}

+ (BOOL)device:(id<FBControlCoreConfiguration_Device>)device andOSPairSupported:(id<FBControlCoreConfiguration_OS>)os
{
  return [os.families containsObject:device.family];
}

@end

/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
  [FBSimulatorControlFrameworkLoader.essentialFrameworks loadPrivateFrameworksOrAbort];
}

#pragma mark Initializers

- (instancetype)initWithNamedDevice:(FBDeviceType *)device os:(FBOSVersion *)os auxillaryDirectory:(NSString *)auxillaryDirectory
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
  FBDeviceModel model = FBDeviceModeliPhone6;
  FBDeviceType *device = FBiOSTargetConfiguration.nameToDevice[model];
  FBOSVersion *os = [FBSimulatorConfiguration newestAvailableOSForDevice:device];
  NSAssert(
    os,
    @"Could not obtain OS for model '%@'. Supported OS Versions for Model %@. All Available OS Versions %@",
    model,
    [FBCollectionInformation oneLineDescriptionFromArray:[FBSimulatorConfiguration supportedOSVersionsForDevice:device]],
    [FBCollectionInformation oneLineDescriptionFromArray:[FBSimulatorConfiguration supportedOSVersions]]
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

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.deviceModel.hash ^ self.osVersionString.hash ^ self.auxillaryDirectory.hash;
}

- (BOOL)isEqual:(FBSimulatorConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }

  return [self.deviceModel isEqualToString:object.deviceModel] &&
         [self.osVersionString isEqualToString:object.osVersionString] &&
         (self.auxillaryDirectory == object.auxillaryDirectory || [self.auxillaryDirectory isEqualToString:object.auxillaryDirectory]);
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Device '%@' | OS Version '%@' | Aux Directory %@ | Architecture '%@'",
    self.deviceModel,
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
    @"device" : self.deviceModel,
    @"os" : self.osVersionString,
    @"aux_directory" : self.auxillaryDirectory ?: NSNull.null,
    @"architecture" : self.architecture
  };
}

#pragma mark - Devices

+ (instancetype)withDevice:(FBDeviceType *)device
{
  return [self.defaultConfiguration withDevice:device];
}

- (instancetype)withDevice:(FBDeviceType *)device
{
  NSParameterAssert(device);
  // Use the current os if compatible
  FBOSVersion *os = self.os;
  if ([FBSimulatorConfiguration device:device andOSPairSupported:os]) {
    return [[FBSimulatorConfiguration alloc] initWithNamedDevice:device os:os auxillaryDirectory:self.auxillaryDirectory];
  }
  // Attempt to find the newest OS for this device, otherwise use what we had before.
  os = [FBSimulatorConfiguration newestAvailableOSForDevice:device] ?: os;
  return [[FBSimulatorConfiguration alloc] initWithNamedDevice:device os:os auxillaryDirectory:self.auxillaryDirectory];
}

+ (instancetype)withDeviceModel:(FBDeviceModel)model
{
  return [self.defaultConfiguration withDeviceModel:model];
}

- (instancetype)withDeviceModel:(FBDeviceModel)model
{
  FBDeviceType *device = FBiOSTargetConfiguration.nameToDevice[model];
  device = device ?: [FBDeviceType genericWithName:model];
  return [self withDevice:device];
}

#pragma mark - OS Versions

+ (instancetype)withOS:(FBOSVersion *)os
{
  return [self.defaultConfiguration withOS:os];
}

- (instancetype)withOS:(FBOSVersion *)os
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
  FBOSVersion *os = FBiOSTargetConfiguration.nameToOSVersion[osName];
  os = os ?: [FBOSVersion genericWithName:osName];
  return [self withOS:os];
}

#pragma mark Auxillary Directory

- (instancetype)withAuxillaryDirectory:(NSString *)auxillaryDirectory
{
  return [[FBSimulatorConfiguration alloc] initWithNamedDevice:self.device os:self.os auxillaryDirectory:self.auxillaryDirectory];
}

#pragma mark Private

+ (BOOL)device:(FBDeviceType *)device andOSPairSupported:(FBOSVersion *)os
{
  return [os.families containsObject:@(device.family)];
}

- (FBDeviceModel)deviceModel
{
  return self.device.model;
}

- (FBOSVersionName)osVersionString
{
  return self.os.name;
}

- (FBArchitecture)architecture
{
  return self.device.simulatorArchitecture;
}

@end

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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

- (instancetype)initWithNamedDevice:(FBDeviceType *)device os:(FBOSVersion *)os
{
  NSParameterAssert(device);
  NSParameterAssert(os);

  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _os = os;

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
  return [[FBSimulatorConfiguration alloc] initWithNamedDevice:device os:os];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc] initWithNamedDevice:self.device os:self.os];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.deviceModel.hash ^ self.osVersionString.hash;
}

- (BOOL)isEqual:(FBSimulatorConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }

  return [self.deviceModel isEqualToString:object.deviceModel] &&
         [self.osVersionString isEqualToString:object.osVersionString];

}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Device '%@' | OS Version '%@'",
    self.deviceModel,
    self.osVersionString
  ];
}

#pragma mark Models

- (instancetype)withDeviceModel:(FBDeviceModel)model
{
  FBDeviceType *device = FBiOSTargetConfiguration.nameToDevice[model];
  device = device ?: [FBDeviceType genericWithName:model];
  return [self withDevice:device];
}

#pragma mark OS Versions

- (instancetype)withOSNamed:(FBOSVersionName)osName
{
  FBOSVersion *os = FBiOSTargetConfiguration.nameToOSVersion[osName];
  os = os ?: [FBOSVersion genericWithName:osName];
  return [self withOS:os];
}

#pragma mark Private

- (instancetype)withOS:(FBOSVersion *)os
{
  NSParameterAssert(os);
  return [[FBSimulatorConfiguration alloc] initWithNamedDevice:self.device os:os ];
}

- (instancetype)withDevice:(FBDeviceType *)device
{
  NSParameterAssert(device);
  // Use the current os if compatible.
  // If os.families is empty, it was probably created via [FBOSVersion +genericWithName:]
  // which has no information about families; in that case we assume it is compatible.
  FBOSVersion *os = self.os;
  if (!os.families.count || [os.families containsObject:@(device.family)]) {
    return [[FBSimulatorConfiguration alloc] initWithNamedDevice:device os:os];
  }
  // Attempt to find the newest OS for this device, otherwise use what we had before.
  os = [FBSimulatorConfiguration newestAvailableOSForDevice:device] ?: os;
  return [[FBSimulatorConfiguration alloc] initWithNamedDevice:device os:os];
}

#pragma mark Private

- (FBDeviceModel)deviceModel
{
  return self.device.model;
}

- (FBOSVersionName)osVersionString
{
  return self.os.name;
}

@end

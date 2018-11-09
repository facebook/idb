/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorConfiguration+CoreSimulator.h"

#import <FBControlCore/FBControlCore.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

#import <objc/runtime.h>

#import "FBSimulatorError.h"
#import "FBSimulatorServiceContext.h"

@implementation FBSimulatorConfiguration (CoreSimulator)

#pragma mark Matching Configuration against Available Versions

+ (FBOSVersion *)newestAvailableOSForDevice:(FBDeviceType *)device
{
  return [[[[FBSimulatorConfiguration supportedOSVersionsForDevice:device] reverseObjectEnumerator] allObjects] firstObject];
}

- (instancetype)newestAvailableOS
{
  FBOSVersion *os = [FBSimulatorConfiguration newestAvailableOSForDevice:self.device];
  NSAssert(os, @"Expected to be able to find any runtime for device %@", self.device);
  return [self withOSNamed:os.name];
}

+ (FBOSVersion *)oldestAvailableOSForDevice:(FBDeviceType *)device
{
  return [[FBSimulatorConfiguration supportedOSVersionsForDevice:device] firstObject];
}

- (instancetype)oldestAvailableOS
{
  FBOSVersion *os = [FBSimulatorConfiguration oldestAvailableOSForDevice:self.device];
  NSAssert(os, @"Expected to be able to find any runtime for device %@", self.device);
  return [self withOSNamed:os.name];
}

+ (instancetype)inferSimulatorConfigurationFromDevice:(SimDevice *)simDevice error:(NSError **)error
{
  FBOSVersionName osName = simDevice.runtime.name;
  FBOSVersion *osVersion = FBiOSTargetConfiguration.nameToOSVersion[osName];
  if (!osVersion) {
    return [[FBSimulatorError
      describeFormat:@"Could not obtain OS Version for %@, perhaps it is unsupported by FBSimulatorControl", osName]
      fail:error];
  }
  FBDeviceModel model = simDevice.deviceType.name;
  FBDeviceType *deviceType = FBiOSTargetConfiguration.nameToDevice[model];
  if (!deviceType) {
    return [[FBSimulatorError
      describeFormat:@"Could not obtain Device for for %@, perhaps it is unsupported by FBSimulatorControl", model]
      fail:error];
  }
  return [[FBSimulatorConfiguration.defaultConfiguration
    withOSNamed:osName]
    withDeviceModel:model];
}

+ (instancetype)inferSimulatorConfigurationFromDeviceSynthesizingMissing:(SimDevice *)simDevice
{
  FBSimulatorConfiguration *configuration = [self inferSimulatorConfigurationFromDevice:simDevice error:nil];
  if (configuration) {
    return configuration;
  }
  FBOSVersionName osName = simDevice.runtime.name;
  FBDeviceModel model = simDevice.deviceType.name;
  return [[FBSimulatorConfiguration.defaultConfiguration
    withOSNamed:osName]
    withDeviceModel:model];
}

- (BOOL)checkRuntimeRequirementsReturningError:(NSError **)error
{
  NSError *innerError = nil;
  SimRuntime *runtime = [self obtainRuntimeWithError:&innerError];
  if (!runtime) {
    return [[[FBSimulatorError
      describeFormat:@"Could not obtain available SimRuntime for configuration %@", self]
      causedBy:innerError]
      failBool:error];
  }
  SimDeviceType *deviceType = [self obtainDeviceTypeWithError:&innerError];
  if (!deviceType) {
    return [[[FBSimulatorError
      describeFormat:@"Could not obtain availableSimDeviceType for configuration %@", self]
      causedBy:innerError]
      failBool:error];
  }
  if (![runtime supportsDeviceType:deviceType]) {
    return [[FBSimulatorError
      describeFormat:@"Device Type %@ does not support Runtime %@", deviceType.name, runtime.name]
      failBool:error];
  }
  return YES;
}

+ (NSArray<FBSimulatorConfiguration *> *)allAvailableDefaultConfigurationsWithLogger:(nullable id<FBControlCoreLogger>)logger
{
  NSArray<NSString *> *absentOSVersions = nil;
  NSArray<NSString *> *absentDeviceTypes = nil;
  NSArray<FBSimulatorConfiguration *> *configurations = [self allAvailableDefaultConfigurationsWithAbsentOSVersionsOut:&absentOSVersions absentDeviceTypesOut:&absentDeviceTypes];
  for (NSString *absentOSVersion in absentOSVersions) {
    [logger.error logFormat:@"OS Version configuration for '%@' is missing", absentOSVersion];
  }
  for (NSString *absentDeviceType in absentDeviceTypes) {
    [logger.error logFormat:@"Device Type configuration for '%@' is missing", absentDeviceType];
  }
  return configurations;
}

+ (NSArray<FBOSVersion *> *)supportedOSVersions
{
  return [FBSimulatorConfiguration osVersionsForRuntimes:self.supportedRuntimes];
}

+ (NSArray<FBOSVersion *> *)supportedOSVersionsForDevice:(FBDeviceType *)device
{
  return [FBSimulatorConfiguration osVersionsForRuntimes:[self supportedRuntimesForDevice:device]];
}

+ (NSArray<FBSimulatorConfiguration *> *)allAvailableDefaultConfigurationsWithAbsentOSVersionsOut:(NSArray<NSString *> **)absentOSVersionsOut absentDeviceTypesOut:(NSArray<NSString *> **)absentDeviceTypesOut
{
  NSMutableArray<FBSimulatorConfiguration *> *configurations = [NSMutableArray array];
  NSMutableArray<NSString *> *absentOSVersions = [NSMutableArray array];
  NSMutableArray<NSString *> *absentDeviceTypes = [NSMutableArray array];
  NSArray<SimDeviceType *> *deviceTypes = self.supportedDeviceTypes;

  for (SimRuntime *runtime in self.supportedRuntimes) {
    if (!runtime.available) {
      continue;
    }
    FBOSVersionName osName = runtime.name;
    if (!FBiOSTargetConfiguration.nameToOSVersion[runtime.name]) {
      [absentOSVersions addObject:runtime.name];
      continue;
    }

    for (SimDeviceType *deviceType in deviceTypes) {
      if (![runtime supportsDeviceType:deviceType]) {
        continue;
      }
      FBDeviceModel model = deviceType.name;
      if (!FBiOSTargetConfiguration.nameToDevice[model]) {
        [absentDeviceTypes addObject:deviceType.name];
        continue;
      }

      FBSimulatorConfiguration *configuration = [[FBSimulatorConfiguration withDeviceModel:model] withOSNamed:osName];
      [configurations addObject:configuration];
    }
  }

  if (absentOSVersionsOut) {
    *absentOSVersionsOut = absentOSVersions;
  }
  if (absentDeviceTypesOut) {
    *absentDeviceTypesOut = absentDeviceTypes;
  }

  return [configurations copy];
}

#pragma mark Obtaining CoreSimulator Classes

- (SimRuntime *)obtainRuntimeWithError:(NSError **)error
{
  NSArray *supportedRuntimes = FBSimulatorConfiguration.supportedRuntimes;
  if (!supportedRuntimes) {
    return [[FBSimulatorError describe:@"Could not obtain supportedRuntimes, perhaps Framework loading failed"] fail:error];
  }
  NSArray *matchingRuntimes = [supportedRuntimes filteredArrayUsingPredicate:self.runtimePredicate];
  if (matchingRuntimes.count == 0) {
    return [[FBSimulatorError describeFormat:@"Could not obtain matching SimRuntime, no matches. Available Runtimes %@", supportedRuntimes] fail:error];
  }
  if (matchingRuntimes.count > 1) {
    return [[FBSimulatorError describeFormat:@"Matching Runtimes is ambiguous: %@", matchingRuntimes] fail:error];
  }
  return [matchingRuntimes firstObject];
}

- (SimDeviceType *)obtainDeviceTypeWithError:(NSError **)error
{
  NSArray *supportedDeviceTypes = FBSimulatorConfiguration.supportedDeviceTypes;
  if (!supportedDeviceTypes) {
    return [[FBSimulatorError describe:@"Could not obtain supportedDeviceTypes, perhaps Framework loading failed"] fail:error];
  }
  NSArray *matchingDeviceTypes = [supportedDeviceTypes filteredArrayUsingPredicate:[FBSimulatorConfiguration deviceTypePredicate:self.device]];
  if (matchingDeviceTypes.count == 0) {
    return [[FBSimulatorError describeFormat:@"Could not obtain matching DeviceTypes, no matches. Available Device Types %@", supportedDeviceTypes] fail:error];
  }
  if (matchingDeviceTypes.count > 1) {
    return [[FBSimulatorError describeFormat:@"Matching Device Types is ambiguous: %@", matchingDeviceTypes] fail:error];
  }
  return [matchingDeviceTypes firstObject];
}

#pragma mark Private

+ (NSArray<FBOSVersion *> *)osVersionsForRuntimes:(NSArray<SimRuntime *> *)runtimes
{
  NSMutableArray<FBOSVersion *> *array = [NSMutableArray array];
  for (SimRuntime *runtime in runtimes) {
    FBOSVersion *os = FBiOSTargetConfiguration.nameToOSVersion[runtime.name];
    if (!os) {
      os = [FBOSVersion genericWithName:runtime.name];
    }
    [array addObject:os];
  }
  return [array copy];
}

+ (NSArray<SimRuntime *> *)supportedRuntimes
{
  return FBSimulatorServiceContext.sharedServiceContext.supportedRuntimes;
}

+ (NSArray<SimDeviceType *> *)supportedDeviceTypes
{
  return FBSimulatorServiceContext.sharedServiceContext.supportedDeviceTypes;
}

+ (NSArray<SimRuntime *> *)supportedRuntimesForDevice:(FBDeviceType *)device
{
  return [[self.supportedRuntimes
    filteredArrayUsingPredicate:[FBSimulatorConfiguration runtimeProductFamilyPredicate:device]]
    sortedArrayUsingComparator:^ NSComparisonResult (SimRuntime *left, SimRuntime *right) {
      NSDecimalNumber *leftVersionNumber = [NSDecimalNumber decimalNumberWithString:left.versionString];
      NSDecimalNumber *rightVersionNumber = [NSDecimalNumber decimalNumberWithString:right.versionString];
      return [leftVersionNumber compare:rightVersionNumber];
    }];
}

- (NSPredicate *)runtimePredicate
{
  return [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [FBSimulatorConfiguration runtimeProductFamilyPredicate:self.device],
    [FBSimulatorConfiguration runtimeNamePredicate:self.os],
    self.runtimeAvailabilityPredicate
  ]];
}

+ (NSPredicate *)runtimeProductFamilyPredicate:(FBDeviceType *)device
{
  return [NSPredicate predicateWithBlock:^ BOOL (SimRuntime *runtime, NSDictionary *_) {
    return [runtime.supportedProductFamilyIDs containsObject:@(device.family)];
  }];
}

+ (NSPredicate *)runtimeNamePredicate:(FBOSVersion *)OS
{
  return [NSPredicate predicateWithBlock:^ BOOL (SimRuntime *runtime, NSDictionary *_) {
    return [runtime.name isEqualToString:OS.name];
  }];
}

- (NSPredicate *)runtimeAvailabilityPredicate
{
  return [NSPredicate predicateWithBlock:^ BOOL (SimRuntime *runtime, NSDictionary *_) {
    return [runtime isAvailableWithError:nil];
  }];
}

+ (NSPredicate *)deviceTypePredicate:(FBDeviceType *)device
{
  return [NSPredicate predicateWithBlock:^ BOOL (SimDeviceType *deviceType, NSDictionary *_) {
    return [deviceType.name isEqualToString:device.model];
  }];
}

@end

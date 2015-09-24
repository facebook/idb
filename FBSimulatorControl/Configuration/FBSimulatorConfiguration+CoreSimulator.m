/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorConfiguration+CoreSimulator.h"

#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBSimulatorConfiguration+Private.h"

@implementation FBSimulatorConfiguration (CoreSimulator)

- (SimRuntime *)runtime
{
  NSDictionary *mapping = self.class.configurationsToAvailableRuntimes;

  for (FBSimulatorConfiguration *configuration in mapping.allKeys) {
    if ([configuration.osVersion isMemberOfClass:self.osVersion.class]) {
      return mapping[configuration];
    }
  }
  return nil;
}

- (SimDeviceType *)deviceType
{
  NSDictionary *mapping = self.class.configurationsToAvailableDeviceTypes;

  for (FBSimulatorConfiguration *configuration in mapping.allKeys) {
    if ([configuration.namedDevice isMemberOfClass:self.namedDevice.class]) {
      return mapping[configuration];
    }
  }
  return nil;
}

- (NSString *)lastScaleKey
{
  return [NSString stringWithFormat:
    @"SimulatorWindowLastScale-%@",
    self.deviceType.identifier
  ];
}

- (NSString *)lastScaleCommandLineSwitch
{
  return [NSString stringWithFormat:@"-%@", self.lastScaleKey];
}

- (instancetype)withRuntime:(SimRuntime *)runtime
{
  return [self iOS:runtime.versionString];
}

- (instancetype)withDeviceType:(SimDeviceType *)deviceType
{
  return [self named:deviceType.name];
}

+ (NSDictionary *)configurationsToAvailableRuntimes
{
  NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
  for (SimRuntime *runtime in SimRuntime.supportedRuntimes) {
    FBSimulatorConfiguration *configuration = [FBSimulatorConfiguration iOS:runtime.versionString];
    if (!configuration) {
      continue;
    }
    if (![runtime isAvailableWithError:nil]) {
      continue;
    }
    dictionary[configuration] = runtime;
  }
  return [dictionary copy];
}

+ (NSDictionary *)configurationsToAvailableDeviceTypes
{
  NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
  for (SimDeviceType *deviceType in SimDeviceType.supportedDeviceTypes) {
    FBSimulatorConfiguration *configuration = [FBSimulatorConfiguration named:deviceType.name];
    if (!configuration) {
      continue;
    }
    dictionary[configuration] = deviceType;
  }
  return [dictionary copy];
}

@end

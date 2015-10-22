/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlConfiguration.h"

#import "FBSimulatorApplication.h"

NSString *const FBSimulatorControlConfigurationDefaultNamePrefix = @"E2E";

@interface FBSimulatorControlConfiguration ()

@property (nonatomic, copy, readwrite) FBSimulatorApplication *simulatorApplication;
@property (nonatomic, copy, readwrite) NSString *deviceSetPath;
@property (nonatomic, assign, readwrite) FBSimulatorManagementOptions options;

@end

@implementation FBSimulatorControlConfiguration

+ (instancetype)configurationWithSimulatorApplication:(FBSimulatorApplication *)simulatorApplication
                                        deviceSetPath:(NSString *)deviceSetPath
                                              options:(FBSimulatorManagementOptions)options
{
  NSParameterAssert(simulatorApplication);

  FBSimulatorControlConfiguration *configuration = [self new];
  configuration.simulatorApplication = simulatorApplication;
  configuration.deviceSetPath = deviceSetPath;
  configuration.options = options;
  return configuration;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [self.class
    configurationWithSimulatorApplication:self.simulatorApplication
    deviceSetPath:self.deviceSetPath
    options:self.options];
}

- (NSUInteger)hash
{
  return self.simulatorApplication.hash | self.deviceSetPath.hash | self.options;
}

- (BOOL)isEqual:(FBSimulatorControlConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return [self.simulatorApplication isEqual:object.simulatorApplication] &&
         ((self.deviceSetPath == nil && object.deviceSetPath == nil) || [self.deviceSetPath isEqual:object.deviceSetPath]) &&
         self.options == object.options;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Pool Config | Set Path %@ | Sim App %@ | Options %ld",
    self.deviceSetPath,
    self.simulatorApplication,
    self.options
  ];
}

@end

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

#pragma mark Initializers

+ (instancetype)configurationWithSimulatorApplication:(FBSimulatorApplication *)simulatorApplication deviceSetPath:(NSString *)deviceSetPath options:(FBSimulatorManagementOptions)options
{
  if (!simulatorApplication) {
    return nil;
  }
  return [[self alloc] initWithSimulatorApplication:simulatorApplication deviceSetPath:deviceSetPath options:options];
}

- (instancetype)initWithSimulatorApplication:(FBSimulatorApplication *)simulatorApplication deviceSetPath:(NSString *)deviceSetPath options:(FBSimulatorManagementOptions)options
{
  NSParameterAssert(simulatorApplication);

  self = [super init];
  if (!self) {
    return nil;
  }

  _simulatorApplication = simulatorApplication;
  _deviceSetPath = deviceSetPath;
  _options = options;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [self.class
    configurationWithSimulatorApplication:self.simulatorApplication
    deviceSetPath:self.deviceSetPath
    options:self.options];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulatorApplication = [coder decodeObjectForKey:NSStringFromSelector(@selector(simulatorApplication))];
  _deviceSetPath = [coder decodeObjectForKey:NSStringFromSelector(@selector(deviceSetPath))];
  _options = [[coder decodeObjectForKey:NSStringFromSelector(@selector(options))] unsignedIntegerValue];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.simulatorApplication forKey:NSStringFromSelector(@selector(simulatorApplication))];
  [coder encodeObject:self.deviceSetPath forKey:NSStringFromSelector(@selector(deviceSetPath))];
  [coder encodeObject:@(self.options) forKey:NSStringFromSelector(@selector(options))];
}

#pragma mark NSObject

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

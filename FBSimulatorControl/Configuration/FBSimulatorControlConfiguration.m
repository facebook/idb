/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlConfiguration.h"

#import <CoreSimulator/CDStructures.h>
#import <CoreSimulator/SimDeviceSet.h>

#import "FBSimulatorApplication.h"
#import "FBSimulatorControl+PrincipalClass.h"

@interface FBSimulatorControlConfiguration ()

@property (nonatomic, copy, readwrite) NSString *deviceSetPath;
@property (nonatomic, assign, readwrite) FBSimulatorManagementOptions options;

@end

@implementation FBSimulatorControlConfiguration

+ (void)initialize
{
  [FBSimulatorControl loadPrivateFrameworksOrAbort];
}

#pragma mark Initializers

+ (instancetype)configurationWithDeviceSetPath:(NSString *)deviceSetPath options:(FBSimulatorManagementOptions)options
{
  return [[self alloc] initWithDeviceSetPath:deviceSetPath options:options];
}

- (instancetype)initWithDeviceSetPath:(NSString *)deviceSetPath options:(FBSimulatorManagementOptions)options
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _deviceSetPath = deviceSetPath;
  _options = options;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [self.class
    configurationWithDeviceSetPath:self.deviceSetPath
    options:self.options];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _deviceSetPath = [coder decodeObjectForKey:NSStringFromSelector(@selector(deviceSetPath))];
  _options = [[coder decodeObjectForKey:NSStringFromSelector(@selector(options))] unsignedIntegerValue];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.deviceSetPath forKey:NSStringFromSelector(@selector(deviceSetPath))];
  [coder encodeObject:@(self.options) forKey:NSStringFromSelector(@selector(options))];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.deviceSetPath.hash | self.options;
}

- (BOOL)isEqual:(FBSimulatorControlConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return ((self.deviceSetPath == nil && object.deviceSetPath == nil) || [self.deviceSetPath isEqual:object.deviceSetPath]) &&
         self.options == object.options;
}

#pragma mark FBJSONSerializable

- (id)jsonSerializableRepresentation
{
  return @{
    NSStringFromSelector(@selector(deviceSetPath)) : self.deviceSetPath ?: NSNull.null,
    NSStringFromSelector(@selector(options)) : @(self.options)
  };
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [self shortDescription];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Pool Config | Set Path %@ | Options %ld",
    self.deviceSetPath,
    self.options
  ];
}

- (NSString *)debugDescription
{
  return [self shortDescription];
}

@end

@implementation FBSimulatorControlConfiguration (Helpers)

+ (NSString *_Nonnull)defaultDeviceSetPath
{
  Class deviceSetClass = NSClassFromString(@"SimDeviceSet");
  NSAssert(deviceSetClass, @"Expected SimDeviceSet to be loaded");
  return [deviceSetClass defaultSetPath] ?: [[deviceSetClass defaultSet] setPath];
}

@end

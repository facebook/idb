/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorControlConfiguration.h"

#import <CoreSimulator/CDStructures.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceSet+Removed.h>

#import <FBControlCore/FBControlCore.h>

#import <objc/runtime.h>

#import "FBSimulatorControl+PrincipalClass.h"
#import "FBSimulatorControlFrameworkLoader.h"

@interface FBSimulatorControlConfiguration ()

@property (nonatomic, copy, readwrite) NSString *deviceSetPath;
@property (nonatomic, assign, readwrite) FBSimulatorManagementOptions options;

@end

@implementation FBSimulatorControlConfiguration

+ (void)initialize
{
  [FBSimulatorControlFrameworkLoader.essentialFrameworks loadPrivateFrameworksOrAbort];
}

#pragma mark Initializers

+ (instancetype)configurationWithDeviceSetPath:(NSString *)deviceSetPath options:(FBSimulatorManagementOptions)options logger:(id<FBControlCoreLogger>)logger reporter:(id<FBEventReporter>)reporter
{
  return [[self alloc] initWithDeviceSetPath:deviceSetPath options:options logger:(logger ?: FBControlCoreGlobalConfiguration.defaultLogger) reporter:reporter];
}

- (instancetype)initWithDeviceSetPath:(NSString *)deviceSetPath options:(FBSimulatorManagementOptions)options logger:(id<FBControlCoreLogger>)logger reporter:(id<FBEventReporter>)reporter
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _deviceSetPath = deviceSetPath;
  _options = options;
  _logger = logger;
  _reporter = reporter;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
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

+ (NSString *)defaultDeviceSetPath
{
  Class deviceSetClass = objc_lookUpClass("SimDeviceSet");
  NSAssert(deviceSetClass, @"Expected SimDeviceSet to be loaded");
  return [deviceSetClass defaultSetPath] ?: [[deviceSetClass defaultSet] setPath];
}

@end

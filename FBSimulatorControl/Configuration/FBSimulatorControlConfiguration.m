/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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

@end

@implementation FBSimulatorControlConfiguration

+ (void)initialize
{
  [FBSimulatorControlFrameworkLoader.essentialFrameworks loadPrivateFrameworksOrAbort];
}

#pragma mark Initializers

+ (instancetype)configurationWithDeviceSetPath:(NSString *)deviceSetPath logger:(id<FBControlCoreLogger>)logger reporter:(id<FBEventReporter>)reporter
{
  return [[self alloc] initWithDeviceSetPath:deviceSetPath logger:(logger ?: FBControlCoreGlobalConfiguration.defaultLogger) reporter:reporter];
}

- (instancetype)initWithDeviceSetPath:(NSString *)deviceSetPath logger:(id<FBControlCoreLogger>)logger reporter:(id<FBEventReporter>)reporter
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _deviceSetPath = deviceSetPath;
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
  return self.deviceSetPath.hash;
}

- (BOOL)isEqual:(FBSimulatorControlConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return ((self.deviceSetPath == nil && object.deviceSetPath == nil) || [self.deviceSetPath isEqual:object.deviceSetPath]);
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Pool Config | Set Path %@",
    self.deviceSetPath
  ];
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

/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorBootConfiguration.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@implementation FBSimulatorBootConfiguration

@synthesize scale = _scale;

#pragma mark Initializers

+ (instancetype)defaultConfiguration
{
  static dispatch_once_t onceToken;
  static FBSimulatorBootConfiguration *configuration;
  dispatch_once(&onceToken, ^{
    configuration = [self new];
  });
  return configuration;
}

static FBSimulatorBootOptions const DefaultBootOptions = FBSimulatorBootOptionsVerifyUsable | FBSimulatorBootOptionsUseNSWorkspace;

- (instancetype)init
{
  return [self initWithOptions:DefaultBootOptions environment:nil scale:nil];
}

- (instancetype)initWithOptions:(FBSimulatorBootOptions)options environment:(NSDictionary<NSString *, NSString *> *)environment scale:(FBScale)scale
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _options = options;
  _environment = environment;
  _scale = scale;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Instances are immutable.
  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBSimulatorBootConfiguration *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }

  return self.options == configuration.options &&
         (self.environment == configuration.environment || [self.environment isEqualToDictionary:configuration.environment]) &&
         (self.scale == configuration.scale || [self.scale isEqualToString:configuration.scale]);
}

- (NSUInteger)hash
{
  return self.options ^ self.environment.hash ^ self.scale.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Scale %@ | Environment %@ | Options %@",
    self.scale,
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.environment],
    [FBCollectionInformation oneLineDescriptionFromArray:[FBSimulatorBootConfiguration stringsFromBootOptions:self.options]]
  ];
}

#pragma mark Accessors

- (nullable NSDecimalNumber *)scaleValue
{
  return self.scale ? [NSDecimalNumber decimalNumberWithString:self.scale] : nil;
}

#pragma mark Options

- (instancetype)withOptions:(FBSimulatorBootOptions)options
{
  return [[self.class alloc] initWithOptions:options environment:self.environment scale:self.scale];
}

#pragma mark Environment

- (instancetype)withBootEnvironment:(nullable NSDictionary<NSString *, NSString *> *)environment
{
  return [[self.class alloc] initWithOptions:self.options environment:environment scale:self.scale];
}

#pragma mark Scale

- (instancetype)withScale:(FBScale)scale
{
  return [[self.class alloc] initWithOptions:self.options environment:self.environment scale:scale];
}

#pragma mark Utility

static NSString *const BootOptionStringConnectBridge = @"Connect Bridge";
static NSString *const BootOptionStringDirectLaunch = @"Direct Launch";
static NSString *const BootOptionStringUseNSWorkspace = @"Use NSWorkspace";

+ (NSArray<NSString *> *)stringsFromBootOptions:(FBSimulatorBootOptions)options
{
  NSMutableArray<NSString *> *strings = [NSMutableArray array];
  if ((options & FBSimulatorBootOptionsConnectBridge) == FBSimulatorBootOptionsConnectBridge) {
    [strings addObject:BootOptionStringConnectBridge];
  }
  if ((options & FBSimulatorBootOptionsEnableDirectLaunch) == FBSimulatorBootOptionsEnableDirectLaunch) {
    [strings addObject:BootOptionStringDirectLaunch];
  }
  if ((options & FBSimulatorBootOptionsUseNSWorkspace) == FBSimulatorBootOptionsUseNSWorkspace) {
    [strings addObject:BootOptionStringUseNSWorkspace];
  }
  return [strings copy];
}

+ (FBSimulatorBootOptions)bootOptionsFromStrings:(NSArray<NSString *> *)strings
{
  FBSimulatorBootOptions options = 0;
  for (NSString *string in strings) {
    if ([string isEqualToString:BootOptionStringConnectBridge]) {
      options = options | FBSimulatorBootOptionsConnectBridge;
    } else if ([string isEqualToString:BootOptionStringDirectLaunch]) {
      options = options | FBSimulatorBootOptionsEnableDirectLaunch;
    } else if ([string isEqualToString:BootOptionStringUseNSWorkspace]) {
      options = options | FBSimulatorBootOptionsUseNSWorkspace;
    }
  }
  return options;
}

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLaunchConfiguration.h"

#import "FBSimulatorConfiguration+Private.h"

@protocol FBSimulatorLaunchConfiguration_Scale <NSObject>

- (NSString *)scaleString;

@end

@interface FBSimulatorLaunchConfiguration_Scale_25 : FBSimulatorConfigurationVariant_Base <FBSimulatorLaunchConfiguration_Scale>
@end

@interface FBSimulatorLaunchConfiguration_Scale_50 : FBSimulatorConfigurationVariant_Base <FBSimulatorLaunchConfiguration_Scale>
@end

@interface FBSimulatorLaunchConfiguration_Scale_75 : FBSimulatorConfigurationVariant_Base <FBSimulatorLaunchConfiguration_Scale>
@end

@interface FBSimulatorLaunchConfiguration_Scale_100 : FBSimulatorConfigurationVariant_Base <FBSimulatorLaunchConfiguration_Scale>
@end

#pragma mark Scales

@implementation FBSimulatorLaunchConfiguration_Scale_25

- (NSString *)scaleString
{
  return @"0.25";
}

@end

@implementation FBSimulatorLaunchConfiguration_Scale_50

- (NSString *)scaleString
{
  return @"0.50";
}

@end

@implementation FBSimulatorLaunchConfiguration_Scale_75

- (NSString *)scaleString
{
  return @"0.75";
}

@end

@implementation FBSimulatorLaunchConfiguration_Scale_100

- (NSString *)scaleString
{
  return @"1.00";
}

@end

@interface FBSimulatorLaunchConfiguration ()

@property (nonatomic, strong, readonly) id<FBSimulatorLaunchConfiguration_Scale> scale;

@end

@implementation FBSimulatorLaunchConfiguration

@synthesize scale = _scale;
@synthesize locale = _locale;

#pragma mark Initializers

+ (instancetype)defaultConfiguration
{
  static dispatch_once_t onceToken;
  static FBSimulatorLaunchConfiguration *configuration;
  dispatch_once(&onceToken, ^{
    id<FBSimulatorLaunchConfiguration_Scale> scale = FBSimulatorLaunchConfiguration_Scale_100.new;
    configuration = [[self alloc] initWithScale:scale locale:nil];
  });
  return configuration;
}

- (instancetype)initWithScale:(id<FBSimulatorLaunchConfiguration_Scale>)scale locale:(NSLocale *)locale
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _scale = scale;
  _locale = locale;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc] initWithScale:self.scale locale:self.locale];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _scale = [coder decodeObjectForKey:NSStringFromSelector(@selector(scale))];
  _locale = [coder decodeObjectForKey:NSStringFromSelector(@selector(locale))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.scale forKey:NSStringFromSelector(@selector(scale))];
  [coder encodeObject:self.locale forKey:NSStringFromSelector(@selector(locale))];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBSimulatorLaunchConfiguration *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }

  return [self.scaleString isEqualToString:configuration.scaleString] &&
         (self.locale == configuration.locale || [self.locale isEqual:configuration.locale]);
}

- (NSUInteger)hash
{
  return self.scaleString.hash ^ self.locale.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Scale %@ | Locale %@",
    self.scaleString,
    self.locale
  ];
}

#pragma mark Accessors

- (NSString *)scaleString
{
  return self.scale.scaleString;
}

#pragma mark Scale

+ (instancetype)scale25Percent
{
  return [self.defaultConfiguration scale25Percent];
}

- (instancetype)scale25Percent
{
  return [self updateScale:FBSimulatorLaunchConfiguration_Scale_25.new];
}

+ (instancetype)scale50Percent
{
  return [self.defaultConfiguration scale50Percent];
}

- (instancetype)scale50Percent
{
  return [self updateScale:FBSimulatorLaunchConfiguration_Scale_50.new];
}

+ (instancetype)scale75Percent
{
  return [self.defaultConfiguration scale75Percent];
}

- (instancetype)scale75Percent
{
  return [self updateScale:FBSimulatorLaunchConfiguration_Scale_75.new];
}

+ (instancetype)scale100Percent
{
  return [self.defaultConfiguration scale25Percent];
}

- (instancetype)scale100Percent
{
  return [self updateScale:FBSimulatorLaunchConfiguration_Scale_100.new];
}

#pragma mark Locale

+ (instancetype)withLocale:(NSLocale *)locale
{
  return [self.defaultConfiguration withLocale:locale];
}

- (instancetype)withLocale:(NSLocale *)locale
{
  return [[self.class alloc] initWithScale:self.scale locale:locale];
}

+ (instancetype)withLocaleNamed:(NSString *)localeName
{
  return [self.defaultConfiguration withLocaleNamed:localeName];
}

- (instancetype)withLocaleNamed:(NSString *)localeIdentifier
{
  return [self withLocale:[NSLocale localeWithLocaleIdentifier:localeIdentifier]];
}

#pragma mark Private

- (instancetype)updateScale:(id<FBSimulatorLaunchConfiguration_Scale>)scale
{
  if (!scale) {
    return nil;
  }
  return [[self.class alloc] initWithScale:scale locale:self.locale];
}

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLaunchConfiguration.h"
#import "FBSimulatorLaunchConfiguration+Private.h"

#import "FBFramebufferVideoConfiguration.h"

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

@implementation FBSimulatorLaunchConfiguration

@synthesize scale = _scale;

#pragma mark Initializers

+ (instancetype)defaultConfiguration
{
  static dispatch_once_t onceToken;
  static FBSimulatorLaunchConfiguration *configuration;
  dispatch_once(&onceToken, ^{
    configuration = [[self alloc]
      initWithOptions:FBSimulatorLaunchOptionsConnectBridge
      scale:FBSimulatorLaunchConfiguration_Scale_100.new
      localizationOverride:nil
      video:FBFramebufferVideoConfiguration.defaultConfiguration];
  });
  return configuration;
}

- (instancetype)initWithOptions:(FBSimulatorLaunchOptions)options scale:(id<FBSimulatorLaunchConfiguration_Scale>)scale localizationOverride:(FBLocalizationOverride *)localizationOverride video:(FBFramebufferVideoConfiguration *)video
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _options = options;
  _scale = scale;
  _localizationOverride = localizationOverride;
  _video = video;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc] initWithOptions:self.options scale:self.scale localizationOverride:self.localizationOverride video:self.video];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _options = [[coder decodeObjectForKey:NSStringFromSelector(@selector(options))] unsignedIntegerValue];
  _scale = [coder decodeObjectForKey:NSStringFromSelector(@selector(scale))];
  _localizationOverride = [coder decodeObjectForKey:NSStringFromSelector(@selector(localizationOverride))];
  _video = [coder decodeObjectForKey:NSStringFromSelector(@selector(video))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:@(self.options) forKey:NSStringFromSelector(@selector(options))];
  [coder encodeObject:self.scale forKey:NSStringFromSelector(@selector(scale))];
  [coder encodeObject:self.localizationOverride forKey:NSStringFromSelector(@selector(localizationOverride))];
  [coder encodeObject:self.video forKey:NSStringFromSelector(@selector(video))];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBSimulatorLaunchConfiguration *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }

  return self.options == configuration.options &&
         [self.scaleString isEqualToString:configuration.scaleString] &&
         (self.localizationOverride == configuration.localizationOverride || [self.localizationOverride isEqual:configuration.localizationOverride]) &&
         (self.video == configuration.video || [self.video isEqual:configuration.video]);
}

- (NSUInteger)hash
{
  return self.options ^ self.scaleString.hash ^ self.localizationOverride.hash ^ self.video.hash;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Scale %@ | %@ | Options %lu",
    self.scaleString,
    self.localizationOverride,
    self.options
  ];
}

- (NSString *)shortDescription
{
  return [self description];
}

- (NSString *)debugDescription
{
  return [self description];
}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  return @{
    NSStringFromSelector(@selector(scale)) : self.scaleString,
    NSStringFromSelector(@selector(localizationOverride)) : self.localizationOverride.jsonSerializableRepresentation ?: NSNull.null
  };
}

#pragma mark Accessors

- (NSString *)scaleString
{
  return self.scale.scaleString;
}

#pragma mark Options

+ (instancetype)withOptions:(FBSimulatorLaunchOptions)options
{
  return [self.defaultConfiguration withOptions:options];
}

- (instancetype)withOptions:(FBSimulatorLaunchOptions)options
{
  return [[self.class alloc] initWithOptions:options scale:self.scale localizationOverride:self.localizationOverride video:self.video];
}

#pragma mark Scale

+ (instancetype)scale25Percent
{
  return [self.defaultConfiguration scale25Percent];
}

- (instancetype)scale25Percent
{
  return [self withScale:FBSimulatorLaunchConfiguration_Scale_25.new];
}

+ (instancetype)scale50Percent
{
  return [self.defaultConfiguration scale50Percent];
}

- (instancetype)scale50Percent
{
  return [self withScale:FBSimulatorLaunchConfiguration_Scale_50.new];
}

+ (instancetype)scale75Percent
{
  return [self.defaultConfiguration scale75Percent];
}

- (instancetype)scale75Percent
{
  return [self withScale:FBSimulatorLaunchConfiguration_Scale_75.new];
}

+ (instancetype)scale100Percent
{
  return [self.defaultConfiguration scale25Percent];
}

- (instancetype)scale100Percent
{
  return [self withScale:FBSimulatorLaunchConfiguration_Scale_100.new];
}

- (instancetype)withScale:(id<FBSimulatorLaunchConfiguration_Scale>)scale
{
  if (!scale) {
    return nil;
  }
  return [[self.class alloc] initWithOptions:self.options scale:scale localizationOverride:self.localizationOverride video:self.video];
}

- (CGSize)scaleSize:(CGSize)size
{
  NSDecimalNumber *scaleNumber = [NSDecimalNumber decimalNumberWithString:self.scaleString];
  CGFloat scale = scaleNumber.doubleValue;
  return CGSizeMake(size.width * scale, size.height * scale);
}

#pragma mark Locale

+ (instancetype)withLocalizationOverride:(nullable FBLocalizationOverride *)localizationOverride
{
  return [self.defaultConfiguration withLocalizationOverride:localizationOverride];
}

- (instancetype)withLocalizationOverride:(nullable FBLocalizationOverride *)localizationOverride
{
  return [[self.class alloc] initWithOptions:self.options scale:self.scale localizationOverride:localizationOverride video:self.video];
}

#pragma mark Video

+ (instancetype)withVideo:(FBFramebufferVideoConfiguration *)video
{
  return [self.defaultConfiguration withVideo:video];
}

- (instancetype)withVideo:(FBFramebufferVideoConfiguration *)video
{
  return [[self.class alloc] initWithOptions:self.options scale:self.scale localizationOverride:self.localizationOverride video:video];
}

@end

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorBootConfiguration.h"

#import "FBSimulatorScale.h"
#import "FBFramebufferConfiguration.h"

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

- (instancetype)init
{
  return [self initWithOptions:0 scale:nil localizationOverride:nil framebuffer:nil];
}

- (instancetype)initWithOptions:(FBSimulatorBootOptions)options scale:(id<FBSimulatorScale>)scale localizationOverride:(FBLocalizationOverride *)localizationOverride framebuffer:(FBFramebufferConfiguration *)framebuffer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _options = options;
  _scale = scale;
  _localizationOverride = localizationOverride;
  _framebuffer = framebuffer;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc] initWithOptions:self.options scale:self.scale localizationOverride:self.localizationOverride framebuffer:self.framebuffer];
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
  _framebuffer = [coder decodeObjectForKey:NSStringFromSelector(@selector(framebuffer))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:@(self.options) forKey:NSStringFromSelector(@selector(options))];
  [coder encodeObject:self.scale forKey:NSStringFromSelector(@selector(scale))];
  [coder encodeObject:self.localizationOverride forKey:NSStringFromSelector(@selector(localizationOverride))];
  [coder encodeObject:self.framebuffer forKey:NSStringFromSelector(@selector(framebuffer))];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBSimulatorBootConfiguration *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }

  return self.options == configuration.options &&
         (self.scaleString == configuration.scaleString || [self.scaleString isEqualToString:configuration.scaleString]) &&
         (self.localizationOverride == configuration.localizationOverride || [self.localizationOverride isEqual:configuration.localizationOverride]) &&
         (self.framebuffer == configuration.framebuffer || [self.framebuffer isEqual:configuration.framebuffer]);
}

- (NSUInteger)hash
{
  return self.options ^ self.scaleString.hash ^ self.localizationOverride.hash ^ self.framebuffer.hash;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Scale %@ | %@ | Options %@ | %@",
    self.scaleString,
    self.localizationOverride ? self.localizationOverride : @"No Locale Override",
    [FBCollectionInformation oneLineDescriptionFromArray:[FBSimulatorBootConfiguration stringsFromLaunchOptions:self.options]],
    self.framebuffer ?: @"No Framebuffer"
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
    @"scale" : self.scaleString ?: NSNull.null,
    @"localization_override" : self.localizationOverride.jsonSerializableRepresentation ?: NSNull.null,
    @"options" : [FBSimulatorBootConfiguration stringsFromLaunchOptions:self.options],
    @"framebuffer" : self.framebuffer.jsonSerializableRepresentation ?: NSNull.null,
  };
}

#pragma mark Accessors

- (nullable NSString *)scaleString
{
  return self.scale.scaleString;
}

- (nullable NSDecimalNumber *)scaleValue
{
  return self.scaleString ? [NSDecimalNumber decimalNumberWithString:self.scaleString] : nil;
}

#pragma mark Options

+ (instancetype)withOptions:(FBSimulatorBootOptions)options
{
  return [self.defaultConfiguration withOptions:options];
}

- (instancetype)withOptions:(FBSimulatorBootOptions)options
{
  return [[self.class alloc] initWithOptions:options scale:self.scale localizationOverride:self.localizationOverride framebuffer:self.framebuffer];
}

#pragma mark Scale

+ (instancetype)scale25Percent
{
  return [self.defaultConfiguration scale25Percent];
}

- (instancetype)scale25Percent
{
  return [self withScale:FBSimulatorScale_25.new];
}

+ (instancetype)scale50Percent
{
  return [self.defaultConfiguration scale50Percent];
}

- (instancetype)scale50Percent
{
  return [self withScale:FBSimulatorScale_50.new];
}

+ (instancetype)scale75Percent
{
  return [self.defaultConfiguration scale75Percent];
}

- (instancetype)scale75Percent
{
  return [self withScale:FBSimulatorScale_75.new];
}

+ (instancetype)scale100Percent
{
  return [self.defaultConfiguration scale25Percent];
}

- (instancetype)scale100Percent
{
  return [self withScale:FBSimulatorScale_100.new];
}

+ (instancetype)withScale:(id<FBSimulatorScale>)scale
{
  return [self.defaultConfiguration withScale:scale];
}

- (instancetype)withScale:(id<FBSimulatorScale>)scale
{
  if (!scale) {
    return nil;
  }
  FBFramebufferConfiguration *framebuffer = [self.framebuffer withScale:scale];
  return [[self.class alloc] initWithOptions:self.options scale:scale localizationOverride:self.localizationOverride framebuffer:framebuffer];
}

#pragma mark Locale

+ (instancetype)withLocalizationOverride:(nullable FBLocalizationOverride *)localizationOverride
{
  return [self.defaultConfiguration withLocalizationOverride:localizationOverride];
}

- (instancetype)withLocalizationOverride:(nullable FBLocalizationOverride *)localizationOverride
{
  return [[self.class alloc] initWithOptions:self.options scale:self.scale localizationOverride:localizationOverride framebuffer:self.framebuffer];
}

#pragma mark Video

+ (instancetype)withFramebuffer:(FBFramebufferConfiguration *)framebuffer
{
  return [self.defaultConfiguration withFramebuffer:framebuffer];
}

- (instancetype)withFramebuffer:(FBFramebufferConfiguration *)framebuffer
{
  return [[self.class alloc] initWithOptions:self.options scale:self.scale localizationOverride:self.localizationOverride framebuffer:framebuffer];
}

#pragma mark Utility

+ (NSArray<NSString *> *)stringsFromLaunchOptions:(FBSimulatorBootOptions)options
{
  NSMutableArray<NSString *> *strings = [NSMutableArray array];
  if ((options & FBSimulatorBootOptionsConnectBridge) == FBSimulatorBootOptionsConnectBridge) {
    [strings addObject:@"Connect Bridge"];
  }
  if ((options & FBSimulatorBootOptionsEnableDirectLaunch) == FBSimulatorBootOptionsEnableDirectLaunch) {
    [strings addObject:@"Direct Launch"];
  }
  if ((options & FBSimulatorBootOptionsUseNSWorkspace) == FBSimulatorBootOptionsUseNSWorkspace) {
    [strings addObject:@"Use NSWorkspace"];
  }
  return [strings copy];
}

@end

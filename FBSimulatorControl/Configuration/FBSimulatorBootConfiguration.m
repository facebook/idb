/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorBootConfiguration.h"

#import "FBFramebufferConfiguration.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeBoot = @"boot";

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
  return [self initWithOptions:DefaultBootOptions environment:nil scale:nil localizationOverride:nil framebuffer:nil];
}

- (instancetype)initWithOptions:(FBSimulatorBootOptions)options environment:(NSDictionary<NSString *, NSString *> *)environment scale:(FBScale)scale localizationOverride:(FBLocalizationOverride *)localizationOverride framebuffer:(FBFramebufferConfiguration *)framebuffer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _options = options;
  _environment = environment;
  _scale = scale;
  _localizationOverride = localizationOverride;
  _framebuffer = framebuffer;

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
         (self.scale == configuration.scale || [self.scale isEqualToString:configuration.scale]) &&
         (self.localizationOverride == configuration.localizationOverride || [self.localizationOverride isEqual:configuration.localizationOverride]) &&
         (self.framebuffer == configuration.framebuffer || [self.framebuffer isEqual:configuration.framebuffer]);
}

- (NSUInteger)hash
{
  return self.options ^ self.environment.hash ^ self.scale.hash ^ self.localizationOverride.hash ^ self.framebuffer.hash;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Scale %@ | Environment %@ | %@ | Options %@ | %@",
    self.scale,
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.environment],
    self.localizationOverride ? self.localizationOverride : @"No Locale Override",
    [FBCollectionInformation oneLineDescriptionFromArray:[FBSimulatorBootConfiguration stringsFromBootOptions:self.options]],
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

static NSString *const KeyEnvironment = @"environment";
static NSString *const KeyFramebuffer = @"framebuffer";
static NSString *const KeyLocalizationOverride = @"localization_override";
static NSString *const KeyOptions = @"options";
static NSString *const KeyScale = @"scale";

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  FBScale scale = [FBCollectionOperations nullableValueForDictionary:json key:KeyScale];
  if (![scale isKindOfClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not a String %@", scale, KeyScale]
      fail:error];
  }
  FBLocalizationOverride *override = nil;
  NSDictionary<NSString *, id> *localizationDictionary = [FBCollectionOperations nullableValueForDictionary:json key:KeyLocalizationOverride];
  if (localizationDictionary) {
    override = [FBLocalizationOverride inflateFromJSON:localizationDictionary error:error];
    if (!override) {
      return nil;
    }
  }
  NSDictionary<NSString *, id> *framebufferDictionary = [FBCollectionOperations nullableValueForDictionary:json key:KeyFramebuffer];
  FBFramebufferConfiguration *framebuffer = nil;
  if (framebufferDictionary) {
    framebuffer = [FBFramebufferConfiguration inflateFromJSON:framebufferDictionary error:error];
    if (!framebuffer) {
      return nil;
    }
  }
  NSArray<NSString *> *bootOptionsStrings = json[KeyOptions];
  if (![FBCollectionInformation isArrayHeterogeneous:bootOptionsStrings withClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not Array<String> | nil | %@", bootOptionsStrings, KeyOptions]
      fail:error];
  }
  FBSimulatorBootOptions bootOptions = [self bootOptionsFromStrings:bootOptionsStrings];
  NSDictionary<NSString *, NSString *> *environment = [FBCollectionOperations nullableValueForDictionary:json key:KeyEnvironment];
  if (environment && ![FBCollectionInformation isDictionaryHeterogeneous:environment keyClass:NSString.class valueClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not Dictionary<String, String> | nil | %@", environment, KeyEnvironment]
      fail:error];
  }

  return [[self alloc] initWithOptions:bootOptions environment:environment scale:scale localizationOverride:override framebuffer:framebuffer];
}

- (NSDictionary *)jsonSerializableRepresentation
{
  return @{
    KeyScale : self.scale ?: NSNull.null,
    KeyLocalizationOverride : self.localizationOverride.jsonSerializableRepresentation ?: NSNull.null,
    KeyOptions : [FBSimulatorBootConfiguration stringsFromBootOptions:self.options],
    KeyFramebuffer : self.framebuffer.jsonSerializableRepresentation ?: NSNull.null,
    KeyEnvironment: self.environment ?: NSNull.null,
  };
}

#pragma mark Accessors

- (nullable NSDecimalNumber *)scaleValue
{
  return self.scale ? [NSDecimalNumber decimalNumberWithString:self.scale] : nil;
}

#pragma mark Options

- (instancetype)withOptions:(FBSimulatorBootOptions)options
{
  return [[self.class alloc] initWithOptions:options environment:self.environment scale:self.scale localizationOverride:self.localizationOverride framebuffer:self.framebuffer];
}

#pragma mark Environment

- (instancetype)withBootEnvironment:(nullable NSDictionary<NSString *, NSString *> *)environment
{
  return [[self.class alloc] initWithOptions:self.options environment:environment scale:self.scale localizationOverride:self.localizationOverride framebuffer:self.framebuffer];
}

#pragma mark Scale

- (instancetype)withScale:(FBScale)scale
{
  if (!scale) {
    return self;
  }
  FBFramebufferConfiguration *framebuffer = [self.framebuffer withScale:scale];
  return [[self.class alloc] initWithOptions:self.options environment:self.environment scale:scale localizationOverride:self.localizationOverride framebuffer:framebuffer];
}

#pragma mark Locale

- (instancetype)withLocalizationOverride:(nullable FBLocalizationOverride *)localizationOverride
{
  return [[self.class alloc] initWithOptions:self.options environment:self.environment scale:self.scale localizationOverride:localizationOverride framebuffer:self.framebuffer];
}

#pragma mark Video

- (instancetype)withFramebuffer:(FBFramebufferConfiguration *)framebuffer
{
  return [[self.class alloc] initWithOptions:self.options environment:self.environment scale:self.scale localizationOverride:self.localizationOverride framebuffer:framebuffer];
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

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeBoot;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  id<FBSimulatorLifecycleCommands> commands = (id<FBSimulatorLifecycleCommands>) target;
  if (![commands conformsToProtocol:@protocol(FBSimulatorLifecycleCommands)]) {
    return [[FBSimulatorError
      describeFormat:@"%@ cannot be booted", target]
      failFuture];
  }
  return [[commands bootWithConfiguration:self] mapReplace:FBiOSTargetContinuationDone(self.class.futureType)];
}

@end

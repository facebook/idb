/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFramebufferConfiguration.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBVideoEncoderConfiguration.h"

@implementation FBFramebufferConfiguration

+ (NSString *)defaultImagePath
{
  return [NSHomeDirectory() stringByAppendingString:@"image.png"];
}

+ (instancetype)configurationWithScale:(nullable FBScale)scale encoder:(FBVideoEncoderConfiguration *)encoder imagePath:(NSString *)imagePath
{
  return [[self alloc] initWithScale:scale encoder:encoder imagePath:imagePath];
}

+ (instancetype)defaultConfiguration
{
  return [self new];
}

- (instancetype)init
{
  return [self initWithScale:nil encoder:FBVideoEncoderConfiguration.defaultConfiguration imagePath:FBFramebufferConfiguration.defaultImagePath];
}

- (instancetype)initWithScale:(nullable FBScale)scale encoder:(FBVideoEncoderConfiguration *)encoder imagePath:(NSString *)imagePath
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _scale = scale;
  _encoder = encoder;
  _imagePath = imagePath;

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
  return self.scale.hash ^ self.encoder.hash ^ self.imagePath.hash;
}

- (BOOL)isEqual:(FBFramebufferConfiguration *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }

  return (self.scale == configuration.scale || [self.scale isEqual:configuration.scale]) &&
         (self.encoder == configuration.encoder || [self.encoder isEqual:configuration.encoder]) &&
         (self.imagePath == configuration.imagePath || [self.imagePath isEqual:configuration.imagePath]);
}

#pragma mark FBJSONSerializable

static NSString *KeyScale = @"scale";
static NSString *KeyEncoder = @"encoder";
static NSString *KeyImagePath = @"image_path";

- (id)jsonSerializableRepresentation
{
  return @{
    KeyScale : self.scale ?: NSNull.null,
    KeyEncoder : self.encoder.jsonSerializableRepresentation,
    KeyImagePath : self.imagePath,
  };
}

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not a Dictionary<String, Any>", json]
      fail:error];
  }
  FBScale scale = [FBCollectionOperations nullableValueForDictionary:json key:KeyScale];
  if (scale && ![scale isKindOfClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not a String for %@", scale, KeyScale]
      fail:error];
  }
  FBVideoEncoderConfiguration *encoder = [FBVideoEncoderConfiguration inflateFromJSON:json[KeyEncoder] error:error];
  if (!encoder) {
    return nil;
  }
  NSString *imagePath = json[KeyImagePath];
  if (![imagePath isKindOfClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not a String for %@", imagePath, KeyImagePath]
      fail:error];
  }
  return [[self alloc] initWithScale:scale encoder:encoder imagePath:imagePath];
}

#pragma mark FBDebugDescribeable

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Scale %@ | Encoder %@ | Image Path %@",
    self.scale,
    self.encoder.description,
    self.imagePath
  ];
}

#pragma mark Scale

+ (instancetype)withScale:(nullable FBScale)scale
{
  return [self.new withScale:scale];
}

- (instancetype)withScale:(nullable FBScale)scale
{
  return [[self.class alloc] initWithScale:scale encoder:self.encoder imagePath:self.imagePath];
}

- (nullable NSDecimalNumber *)scaleValue
{
  return self.scale ? [NSDecimalNumber decimalNumberWithString:self.scale] : nil;
}

- (CGSize)scaleSize:(CGSize)size
{
  NSDecimalNumber *scaleNumber = self.scaleValue;
  if (!self.scaleValue) {
    return size;
  }
  CGFloat scale = scaleNumber.doubleValue;
  return CGSizeMake(size.width * scale, size.height * scale);
}

#pragma mark Encoder

+ (instancetype)withEncoder:(FBVideoEncoderConfiguration *)encoder
{
  return [self.new withEncoder:encoder];
}

- (instancetype)withEncoder:(FBVideoEncoderConfiguration *)encoder
{
  return [[self.class alloc] initWithScale:self.scale encoder:encoder imagePath:self.imagePath];
}

#pragma mark Diagnostics

+ (instancetype)withImagePath:(NSString *)imagePath
{
  return [self.new withImagePath:imagePath];
}

- (instancetype)withImagePath:(NSString *)imagePath
{
  return [[self.class alloc] initWithScale:self.scale encoder:self.encoder imagePath:imagePath];
}

#pragma mark Simulators

- (instancetype)inSimulator:(FBSimulator *)simulator
{
  FBVideoEncoderConfiguration *encoder = [self.encoder withFilePath:FBiOSTargetDefaultVideoPath(simulator.auxillaryDirectory)];
  return [[self withEncoder:encoder] withImagePath:FBiOSTargetDefaultScreenshotPath(simulator.auxillaryDirectory)];
}

@end

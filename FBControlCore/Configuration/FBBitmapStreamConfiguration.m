/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBBitmapStreamConfiguration.h"

#import "FBControlCoreError.h"
#import "FBCollectionInformation.h"
#import "FBCollectionOperations.h"

FBBitmapStreamEncoding const FBBitmapStreamEncodingH264 = @"h264";
FBBitmapStreamEncoding const FBBitmapStreamEncodingBGRA = @"bgra";

@implementation FBBitmapStreamConfiguration

#pragma mark Initializers

+ (instancetype)configurationWithEncoding:(FBBitmapStreamEncoding)encoding framesPerSecond:(nullable NSNumber *)framesPerSecond
{
  return [[self alloc] initWithEncoding:encoding framesPerSecond:framesPerSecond];
}

- (instancetype)initWithEncoding:(FBBitmapStreamEncoding)encoding framesPerSecond:(nullable NSNumber *)framesPerSecond
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _encoding = encoding;
  _framesPerSecond = framesPerSecond;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBBitmapStreamConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }

  return (self.encoding == object.encoding || [self.encoding isEqualToString:object.encoding])
      && (self.framesPerSecond == object.framesPerSecond || [self.framesPerSecond isEqualToNumber:object.framesPerSecond]);
}

- (NSUInteger)hash
{
  return self.encoding.hash ^ self.framesPerSecond.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Encoding %@ | FPS %@",
    self.encoding,
    self.framesPerSecond
  ];
}

#pragma mark JSON

static NSString *const KeyStreamEncoding = @"encoding";
static NSString *const KeyFramesPerSecond = @"frames_per_second";

- (id)jsonSerializableRepresentation
{
  return @{
    KeyStreamEncoding: self.encoding,
    KeyFramesPerSecond: self.framesPerSecond ?: NSNull.null,
  };
}

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Dictionary<String, Object>", json]
      fail:error];
  }
  FBBitmapStreamEncoding encoding = json[KeyStreamEncoding];
  if (![encoding isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a String for %@", encoding, KeyStreamEncoding]
      fail:error];
  }
  NSNumber *framesPerSecond = [FBCollectionOperations nullableValueForDictionary:json key:KeyFramesPerSecond];
  if (framesPerSecond && ![framesPerSecond isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Number for %@", framesPerSecond, KeyFramesPerSecond]
      fail:error];
  }
  return [[self alloc] initWithEncoding:encoding framesPerSecond:framesPerSecond];
}

@end

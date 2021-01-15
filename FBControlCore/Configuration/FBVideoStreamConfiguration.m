/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBVideoStreamConfiguration.h"

#import "FBControlCoreError.h"
#import "FBCollectionInformation.h"
#import "FBCollectionOperations.h"

FBVideoStreamEncoding const FBVideoStreamEncodingH264 = @"h264";
FBVideoStreamEncoding const FBVideoStreamEncodingBGRA = @"bgra";
FBVideoStreamEncoding const FBVideoStreamEncodingMJPEG = @"mjpeg";
FBVideoStreamEncoding const FBVideoStreamEncodingMinicap = @"minicap";

@implementation FBVideoStreamConfiguration

#pragma mark Initializers

- (instancetype)initWithEncoding:(FBVideoStreamEncoding)encoding framesPerSecond:(nullable NSNumber *)framesPerSecond compressionQuality:(nullable NSNumber *)compressionQuality scaleFactor:(nullable NSNumber *)scaleFactor
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _encoding = encoding;
  _framesPerSecond = framesPerSecond;
  _compressionQuality = compressionQuality ?: @0.2;
  _scaleFactor = scaleFactor;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Object is immutable.
  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBVideoStreamConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }

  return (self.encoding == object.encoding || [self.encoding isEqualToString:object.encoding])
      && (self.framesPerSecond == object.framesPerSecond || [self.framesPerSecond isEqualToNumber:object.framesPerSecond])
      && (self.compressionQuality == object.compressionQuality || [self.compressionQuality isEqualToNumber:object.compressionQuality])
      && (self.scaleFactor == object.scaleFactor || [self.scaleFactor isEqualToNumber:object.scaleFactor]);
}

- (NSUInteger)hash
{
  return self.encoding.hash ^ self.framesPerSecond.hash ^ self.compressionQuality.hash ^ self.scaleFactor.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Encoding %@ | FPS %@ | Quality %@ | Scale %@",
    self.encoding,
    self.framesPerSecond,
    self.compressionQuality,
    self.scaleFactor
  ];
}

@end

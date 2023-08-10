/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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

- (instancetype)initWithEncoding:(FBVideoStreamEncoding)encoding framesPerSecond:(nullable NSNumber *)framesPerSecond compressionQuality:(nullable NSNumber *)compressionQuality scaleFactor:(nullable NSNumber *)scaleFactor avgBitrate:(nullable NSNumber *)avgBitrate keyFrameRate:(nullable NSNumber *) keyFrameRate
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _encoding = encoding;
  _framesPerSecond = framesPerSecond;
  _compressionQuality = compressionQuality ?: @0.2;
  _scaleFactor = scaleFactor;
  _avgBitrate = avgBitrate;
  _keyFrameRate = keyFrameRate ?: @10.0;

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
      && (self.scaleFactor == object.scaleFactor || [self.scaleFactor isEqualToNumber:object.scaleFactor])
      && (self.avgBitrate == object.avgBitrate || [self.avgBitrate isEqualToNumber:object.avgBitrate])
      && (self.keyFrameRate == object.keyFrameRate || [self.keyFrameRate isEqualToNumber:object.keyFrameRate]);
}

- (NSUInteger)hash
{
  return self.encoding.hash ^ self.framesPerSecond.hash ^ self.compressionQuality.hash ^ self.scaleFactor.hash ^ self.avgBitrate.hash ^ self.keyFrameRate.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Encoding %@ | FPS %@ | Quality %@ | Scale %@ | Avg Bitrate %@ | Key frame rate %@",
    self.encoding,
    self.framesPerSecond,
    self.compressionQuality,
    self.scaleFactor,
    self.avgBitrate,
    self.keyFrameRate
  ];
}

@end

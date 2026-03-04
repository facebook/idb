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

@implementation FBVideoStreamRateControl

+ (instancetype)quality:(NSNumber *)quality
{
  FBVideoStreamRateControl *rc = [[FBVideoStreamRateControl alloc] init];
  rc->_mode = FBVideoStreamRateControlModeConstantQuality;
  rc->_value = [quality copy];
  return rc;
}

+ (instancetype)bitrate:(NSNumber *)bitrate
{
  FBVideoStreamRateControl *rc = [[FBVideoStreamRateControl alloc] init];
  rc->_mode = FBVideoStreamRateControlModeAverageBitrate;
  rc->_value = [bitrate copy];
  return rc;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Immutable.
  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBVideoStreamRateControl *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return self.mode == object.mode && [self.value isEqualToNumber:object.value];
}

- (NSUInteger)hash
{
  return @(self.mode).hash ^ self.value.hash;
}

- (NSString *)description
{
  switch (self.mode) {
    case FBVideoStreamRateControlModeConstantQuality:
      return [NSString stringWithFormat:@"Quality %@", self.value];
    case FBVideoStreamRateControlModeAverageBitrate: {
      double bps = self.value.doubleValue;
      if (bps >= 1000000.0) {
        return [NSString stringWithFormat:@"Bitrate %.1f Mbps", bps / 1000000.0];
      } else {
        return [NSString stringWithFormat:@"Bitrate %.0f kbps", bps / 1000.0];
      }
    }
    default:
      return [NSString stringWithFormat:@"RateControl(%lu, %@)", (unsigned long)self.mode, self.value];
  }
}

@end

@implementation FBVideoStreamConfiguration

#pragma mark Initializers

- (instancetype)initWithEncoding:(FBVideoStreamEncoding)encoding framesPerSecond:(nullable NSNumber *)framesPerSecond rateControl:(nullable FBVideoStreamRateControl *)rateControl scaleFactor:(nullable NSNumber *)scaleFactor keyFrameRate:(nullable NSNumber *)keyFrameRate
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _encoding = encoding;
  _framesPerSecond = framesPerSecond;
  _rateControl = [rateControl copy] ?: [FBVideoStreamRateControl quality:@0.2];
  _scaleFactor = scaleFactor;
  _keyFrameRate = keyFrameRate ?: @1.0;

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
      && [self.rateControl isEqual:object.rateControl]
      && (self.scaleFactor == object.scaleFactor || [self.scaleFactor isEqualToNumber:object.scaleFactor])
      && (self.keyFrameRate == object.keyFrameRate || [self.keyFrameRate isEqualToNumber:object.keyFrameRate]);
}

- (NSUInteger)hash
{
  return self.encoding.hash ^ self.framesPerSecond.hash ^ self.rateControl.hash ^ self.scaleFactor.hash ^ self.keyFrameRate.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Encoding %@ | FPS %@ | Rate Control %@ | Scale %@ | Key frame rate %@",
    self.encoding,
    self.framesPerSecond,
    self.rateControl,
    self.scaleFactor,
    self.keyFrameRate
  ];
}

@end

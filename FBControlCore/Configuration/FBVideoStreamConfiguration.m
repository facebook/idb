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
FBVideoStreamEncoding const FBVideoStreamEncodingHEVC = @"hevc";
FBVideoStreamEncoding const FBVideoStreamEncodingBGRA = @"bgra";
FBVideoStreamEncoding const FBVideoStreamEncodingMJPEG = @"mjpeg";
FBVideoStreamEncoding const FBVideoStreamEncodingMinicap = @"minicap";

FBVideoStreamCodec const FBVideoStreamCodecH264 = @"h264";
FBVideoStreamCodec const FBVideoStreamCodecHEVC = @"hevc";
FBVideoStreamTransport const FBVideoStreamTransportAnnexB = @"annex-b";
FBVideoStreamTransport const FBVideoStreamTransportMPEGTS = @"mpegts";
FBVideoStreamTransport const FBVideoStreamTransportFMP4 = @"fmp4";

@implementation FBVideoStreamFormat

+ (instancetype)compressedVideoWithCodec:(FBVideoStreamCodec)codec
                               transport:(FBVideoStreamTransport)transport
{
  FBVideoStreamFormat *fmt = [[FBVideoStreamFormat alloc] init];
  fmt->_type = FBVideoStreamFormatTypeCompressedVideo;
  fmt->_codec = [codec copy];
  fmt->_transport = [transport copy];
  return fmt;
}

+ (instancetype)mjpeg
{
  FBVideoStreamFormat *fmt = [[FBVideoStreamFormat alloc] init];
  fmt->_type = FBVideoStreamFormatTypeMJPEG;
  return fmt;
}

+ (instancetype)minicap
{
  FBVideoStreamFormat *fmt = [[FBVideoStreamFormat alloc] init];
  fmt->_type = FBVideoStreamFormatTypeMinicap;
  return fmt;
}

+ (instancetype)bgra
{
  FBVideoStreamFormat *fmt = [[FBVideoStreamFormat alloc] init];
  fmt->_type = FBVideoStreamFormatTypeBGRA;
  return fmt;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Immutable.
  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBVideoStreamFormat *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  if (self.type != object.type) {
    return NO;
  }
  if (self.type == FBVideoStreamFormatTypeCompressedVideo) {
    return [self.codec isEqualToString:object.codec]
        && [self.transport isEqualToString:object.transport];
  }
  return YES;
}

- (NSUInteger)hash
{
  return @(self.type).hash ^ self.codec.hash ^ self.transport.hash;
}

- (NSString *)description
{
  switch (self.type) {
    case FBVideoStreamFormatTypeCompressedVideo:
      return [NSString stringWithFormat:@"%@ over %@", self.codec, self.transport];
    case FBVideoStreamFormatTypeMJPEG:
      return @"MJPEG";
    case FBVideoStreamFormatTypeMinicap:
      return @"Minicap";
    case FBVideoStreamFormatTypeBGRA:
      return @"BGRA";
    default:
      return [NSString stringWithFormat:@"Format(%lu)", (unsigned long)self.type];
  }
}

@end

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

- (instancetype)initWithFormat:(FBVideoStreamFormat *)format framesPerSecond:(nullable NSNumber *)framesPerSecond rateControl:(nullable FBVideoStreamRateControl *)rateControl scaleFactor:(nullable NSNumber *)scaleFactor keyFrameRate:(nullable NSNumber *)keyFrameRate
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _format = [format copy];
  _framesPerSecond = framesPerSecond;
  _rateControl = [rateControl copy] ?: [FBVideoStreamRateControl quality:@0.75];
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

  return [self.format isEqual:object.format]
      && (self.framesPerSecond == object.framesPerSecond || [self.framesPerSecond isEqualToNumber:object.framesPerSecond])
      && [self.rateControl isEqual:object.rateControl]
      && (self.scaleFactor == object.scaleFactor || [self.scaleFactor isEqualToNumber:object.scaleFactor])
      && (self.keyFrameRate == object.keyFrameRate || [self.keyFrameRate isEqualToNumber:object.keyFrameRate]);
}

- (NSUInteger)hash
{
  return self.format.hash ^ self.framesPerSecond.hash ^ self.rateControl.hash ^ self.scaleFactor.hash ^ self.keyFrameRate.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Format %@ | FPS %@ | Rate Control %@ | Scale %@ | Key frame rate %@",
    self.format,
    self.framesPerSecond,
    self.rateControl,
    self.scaleFactor,
    self.keyFrameRate
  ];
}

@end

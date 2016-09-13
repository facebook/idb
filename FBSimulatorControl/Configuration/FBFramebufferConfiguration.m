/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferConfiguration.h"

#import <AVFoundation/AVFoundation.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulatorScale.h"

@implementation FBFramebufferConfiguration

+ (instancetype)defaultConfiguration
{
  return [self new];
}

+ (instancetype)prudentConfiguration
{
  return [FBFramebufferConfiguration
    withDiagnostic:nil
    scale:nil
    videoOptions:FBFramebufferVideoOptionsImmediateFrameStart | FBFramebufferVideoOptionsFinalFrame
    timescale:1000
    roundingMethod:kCMTimeRoundingMethod_QuickTime
    fileType:AVFileTypeQuickTimeMovie];
}

+ (instancetype)withDiagnostic:(nullable FBDiagnostic *)diagnostic scale:(nullable id<FBSimulatorScale>)scale videoOptions:(FBFramebufferVideoOptions)videoOptions timescale:(CMTimeScale)timescale roundingMethod:(CMTimeRoundingMethod)roundingMethod fileType:(nullable NSString *)fileType
{
  return [[FBFramebufferConfiguration alloc] initWithDiagnostic:diagnostic scale:scale videoOptions:videoOptions timescale:timescale roundingMethod:roundingMethod fileType:fileType];
}

- (instancetype)init
{
  return [self initWithDiagnostic:nil scale:nil videoOptions:FBFramebufferVideoOptionsImmediateFrameStart | FBFramebufferVideoOptionsFinalFrame timescale:1000 roundingMethod:kCMTimeRoundingMethod_RoundTowardZero fileType:AVFileTypeMPEG4];
}

- (instancetype)initWithDiagnostic:(nullable FBDiagnostic *)diagnostic scale:(nullable id<FBSimulatorScale>)scale videoOptions:(FBFramebufferVideoOptions)videoOptions timescale:(CMTimeScale)timescale roundingMethod:(CMTimeRoundingMethod)roundingMethod fileType:(nullable NSString *)fileType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _diagnostic = diagnostic;
  _scale = scale;
  _videoOptions = videoOptions;
  _timescale = timescale;
  _roundingMethod = roundingMethod;
  _fileType = fileType;

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
  return self.diagnostic.hash ^ self.scale.hash ^ self.videoOptions ^ (NSUInteger) self.timescale ^ (NSUInteger) self.roundingMethod ^ self.fileType.hash;
}

- (BOOL)isEqual:(FBFramebufferConfiguration *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }

  return (self.diagnostic == configuration.diagnostic || [self.diagnostic isEqual:configuration.diagnostic]) &&
         (self.scale == configuration.scale || [self.scale isEqual:configuration.scale]) &&
         (self.videoOptions == configuration.videoOptions) &&
         (self.timescale == configuration.timescale) &&
         (self.roundingMethod == configuration.roundingMethod) &&
         (self.fileType == configuration.fileType || [self.fileType isEqual:configuration.fileType]);
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)decoder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _diagnostic = [decoder decodeObjectForKey:NSStringFromSelector(@selector(diagnostic))];
  _scale = [decoder decodeObjectForKey:NSStringFromSelector(@selector(scale))];
  _videoOptions = [[decoder decodeObjectForKey:NSStringFromSelector(@selector(videoOptions))] unsignedIntegerValue];
  _timescale = [decoder decodeInt32ForKey:NSStringFromSelector(@selector(timescale))];
  _roundingMethod = [[decoder decodeObjectForKey:NSStringFromSelector(@selector(roundingMethod))] unsignedIntValue];
  _fileType = [decoder decodeObjectForKey:NSStringFromSelector(@selector(fileType))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.diagnostic forKey:NSStringFromSelector(@selector(diagnostic))];
  [coder encodeObject:self.scale forKey:NSStringFromSelector(@selector(scale))];
  [coder encodeObject:@(self.videoOptions) forKey:NSStringFromSelector(@selector(videoOptions))];
  [coder encodeInt32:self.timescale forKey:NSStringFromSelector(@selector(timescale))];
  [coder encodeObject:@(self.roundingMethod) forKey:NSStringFromSelector(@selector(roundingMethod))];
  [coder encodeObject:self.fileType forKey:NSStringFromSelector(@selector(fileType))];
}

#pragma mark FBJSONSerializable

- (id)jsonSerializableRepresentation
{
  return @{
    @"diagnostic" : self.diagnostic.jsonSerializableRepresentation ?: NSNull.null,
    @"scale" : self.scale.scaleString ?: NSNull.null,
    @"video_options" : [FBFramebufferConfiguration stringsFromVideoOptions:self.videoOptions],
    @"timescale" : @(self.timescale),
    @"rounding_method" : @(self.roundingMethod),
    @"file_type" : self.fileType ?: NSNull.null,
  };
}

#pragma mark FBDebugDescribeable

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Options %@ | Scale %@ | Timescale %d | Rounding Method %d",
    [FBCollectionInformation oneLineDescriptionFromArray:[FBFramebufferConfiguration stringsFromVideoOptions:self.videoOptions]],
    self.scale.scaleString,
    self.timescale,
    self.roundingMethod
  ];
}

- (NSString *)debugDescription
{
  return self.shortDescription;
}

- (NSString *)description
{
  return self.shortDescription;
}

#pragma mark Diagnostics

+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic
{
  return [self.defaultConfiguration withDiagnostic:diagnostic];
}

- (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic
{
  return [[self.class alloc] initWithDiagnostic:diagnostic scale:self.scale videoOptions:self.videoOptions timescale:self.timescale roundingMethod:self.roundingMethod fileType:self.fileType];
}

#pragma mark Autorecord

+ (instancetype)withVideoOptions:(FBFramebufferVideoOptions)videoOptions
{
  return [self.defaultConfiguration withVideoOptions:videoOptions];
}

- (instancetype)withVideoOptions:(FBFramebufferVideoOptions)videoOptions
{
  return [[self.class alloc] initWithDiagnostic:self.diagnostic scale:self.scale videoOptions:videoOptions timescale:self.timescale roundingMethod:self.roundingMethod fileType:self.fileType];
}

#pragma mark Timescale

+ (instancetype)withTimescale:(CMTimeScale)timescale
{
  return [self.defaultConfiguration withTimescale:timescale];
}

- (instancetype)withTimescale:(CMTimeScale)timescale
{
  return [[self.class alloc] initWithDiagnostic:self.diagnostic scale:self.scale videoOptions:self.videoOptions timescale:timescale roundingMethod:self.roundingMethod fileType:self.fileType];
}

#pragma mark Rounding

+ (instancetype)withRoundingMethod:(CMTimeRoundingMethod)roundingMethod
{
  return [self.defaultConfiguration withRoundingMethod:roundingMethod];
}

- (instancetype)withRoundingMethod:(CMTimeRoundingMethod)roundingMethod
{
  return [[self.class alloc] initWithDiagnostic:self.diagnostic scale:self.scale videoOptions:self.videoOptions timescale:self.timescale roundingMethod:roundingMethod fileType:self.fileType];
}

#pragma mark File Type

+ (instancetype)withFileType:(NSString *)fileType
{
  return [self.defaultConfiguration withFileType:fileType];
}

- (instancetype)withFileType:(NSString *)fileType
{
  return [[self.class alloc] initWithDiagnostic:self.diagnostic scale:self.scale videoOptions:self.videoOptions timescale:self.timescale roundingMethod:self.roundingMethod fileType:fileType];
}

#pragma mark Scale

+ (instancetype)withScale:(nullable id<FBSimulatorScale>)scale
{
  return [self.defaultConfiguration withScale:scale];
}

- (instancetype)withScale:(nullable id<FBSimulatorScale>)scale
{
  return [[self.class alloc] initWithDiagnostic:self.diagnostic scale:scale videoOptions:self.videoOptions timescale:self.timescale roundingMethod:self.roundingMethod fileType:self.fileType];
}

- (nullable NSDecimalNumber *)scaleValue
{
  return self.scale.scaleString ? [NSDecimalNumber decimalNumberWithString:self.scale.scaleString] : nil;
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

#pragma mark Private

+ (NSArray<NSString *> *)stringsFromVideoOptions:(FBFramebufferVideoOptions)options
{
  NSMutableArray<NSString *> *strings = [NSMutableArray array];
  if ((options & FBFramebufferVideoOptionsAutorecord) == FBFramebufferVideoOptionsAutorecord) {
    [strings addObject:@"Autorecord"];
  }
  if ((options & FBFramebufferVideoOptionsImmediateFrameStart) == FBFramebufferVideoOptionsImmediateFrameStart) {
    [strings addObject:@"Immediate Frame Start"];
  }
  if ((options & FBFramebufferVideoOptionsFinalFrame) == FBFramebufferVideoOptionsFinalFrame) {
    [strings addObject:@"Final Frame"];
  }
  return [strings copy];
}

@end

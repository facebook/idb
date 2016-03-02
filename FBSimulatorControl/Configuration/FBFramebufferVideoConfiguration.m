/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferVideoConfiguration.h"

#import <AVFoundation/AVFoundation.h>

#import "FBDiagnostic.h"

@implementation FBFramebufferVideoConfiguration

+ (instancetype)defaultConfiguration
{
  return [FBFramebufferVideoConfiguration withDiagnostic:nil autorecord:NO timescale:1000 roundingMethod:kCMTimeRoundingMethod_RoundTowardZero fileType:AVFileTypeMPEG4];
}

+ (instancetype)prudentConfiguration
{
  return [FBFramebufferVideoConfiguration withDiagnostic:nil autorecord:NO timescale:1000 roundingMethod:kCMTimeRoundingMethod_QuickTime fileType:AVFileTypeQuickTimeMovie];
}

+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic autorecord:(BOOL)autorecord timescale:(CMTimeScale)timescale roundingMethod:(CMTimeRoundingMethod)roundingMethod fileType:(NSString *)fileType
{
  return [[FBFramebufferVideoConfiguration alloc] initWithDiagnostic:diagnostic autorecord:autorecord timescale:timescale roundingMethod:roundingMethod fileType:fileType];
}

- (instancetype)initWithDiagnostic:(FBDiagnostic *)diagnostic autorecord:(BOOL)autorecord timescale:(CMTimeScale)timescale roundingMethod:(CMTimeRoundingMethod)roundingMethod fileType:(NSString *)fileType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _diagnostic = diagnostic;
  _autorecord = autorecord;
  _timescale = timescale;
  _roundingMethod = roundingMethod;
  _fileType = fileType;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc] initWithDiagnostic:self.diagnostic autorecord:self.autorecord timescale:self.timescale roundingMethod:self.roundingMethod fileType:self.fileType];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.diagnostic.hash ^ (NSUInteger) self.autorecord ^ (NSUInteger) self.timescale ^ (NSUInteger) self.roundingMethod ^ self.fileType.hash;
}

- (BOOL)isEqual:(FBFramebufferVideoConfiguration *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }

  return (self.diagnostic == configuration.diagnostic || [self.diagnostic isEqual:configuration.diagnostic]) &&
         (self.autorecord == configuration.autorecord) &&
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
  _autorecord = [decoder decodeBoolForKey:NSStringFromSelector(@selector(autorecord))];
  _timescale = [decoder decodeInt32ForKey:NSStringFromSelector(@selector(timescale))];
  _roundingMethod = [[decoder decodeObjectForKey:NSStringFromSelector(@selector(roundingMethod))] unsignedIntValue];
  _fileType = [decoder decodeObjectForKey:NSStringFromSelector(@selector(fileType))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.diagnostic forKey:NSStringFromSelector(@selector(diagnostic))];
  [coder encodeBool:self.autorecord forKey:NSStringFromSelector(@selector(autorecord))];
  [coder encodeInt32:self.timescale forKey:NSStringFromSelector(@selector(timescale))];
  [coder encodeObject:@(self.roundingMethod) forKey:NSStringFromSelector(@selector(roundingMethod))];
  [coder encodeObject:self.fileType forKey:NSStringFromSelector(@selector(fileType))];
}

#pragma mark FBJSONSerializationDescribeable

- (id)jsonSerializableRepresentation
{
  return @{
    NSStringFromSelector(@selector(diagnostic)) : self.diagnostic.jsonSerializableRepresentation ?: NSNull.null,
    NSStringFromSelector(@selector(autorecord)) : @(self.autorecord),
    NSStringFromSelector(@selector(timescale)) : @(self.timescale),
    NSStringFromSelector(@selector(roundingMethod)) : @(self.roundingMethod),
    NSStringFromSelector(@selector(fileType)) : self.fileType ?: NSNull.null
  };
}

#pragma mark FBDebugDescribeable

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:@"Autorecord %hhd | Timescale %d | Rounding Method %d", self.autorecord, self.timescale, self.roundingMethod];
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
  return [[self.class alloc] initWithDiagnostic:diagnostic autorecord:self.autorecord timescale:self.timescale roundingMethod:self.roundingMethod fileType:self.fileType];
}

#pragma mark Autorecord

+ (instancetype)withAutorecord:(BOOL)autorecord
{
  return [self.defaultConfiguration withAutorecord:autorecord];
}

- (instancetype)withAutorecord:(BOOL)autorecord
{
  return [[self.class alloc] initWithDiagnostic:self.diagnostic autorecord:autorecord timescale:self.timescale roundingMethod:self.roundingMethod fileType:self.fileType];
}

#pragma mark Timescale

+ (instancetype)withTimescale:(CMTimeScale)timescale
{
  return [self.defaultConfiguration withTimescale:timescale];
}

- (instancetype)withTimescale:(CMTimeScale)timescale
{
  return [[self.class alloc] initWithDiagnostic:self.diagnostic autorecord:self.autorecord timescale:timescale roundingMethod:self.roundingMethod fileType:self.fileType];
}

#pragma mark Rounding

+ (instancetype)withRoundingMethod:(CMTimeRoundingMethod)roundingMethod
{
  return [self.defaultConfiguration withRoundingMethod:roundingMethod];
}

- (instancetype)withRoundingMethod:(CMTimeRoundingMethod)roundingMethod
{
  return [[self.class alloc] initWithDiagnostic:self.diagnostic autorecord:self.autorecord timescale:self.timescale roundingMethod:roundingMethod fileType:self.fileType];
}

#pragma mark File Type

+ (instancetype)withFileType:(NSString *)fileType
{
  return [self withFileType:fileType];
}

- (instancetype)withFileType:(NSString *)fileType
{
  return [[self.class alloc] initWithDiagnostic:self.diagnostic autorecord:self.autorecord timescale:self.timescale roundingMethod:self.roundingMethod fileType:fileType];
}

@end

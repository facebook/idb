/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBVideoEncoderConfiguration.h"

#import <AVFoundation/AVFoundation.h>

#import "FBSimulatorError.h"

@implementation FBVideoEncoderConfiguration

#pragma mark Initializers

+ (NSString *)defaultVideoPath
{
  return [NSHomeDirectory() stringByAppendingString:@"video.mp4"];
}

+ (instancetype)defaultConfiguration
{
  return [self new];
}

+ (instancetype)prudentConfiguration
{
  return [[FBVideoEncoderConfiguration alloc]
    initWithOptions:FBVideoEncoderOptionsImmediateFrameStart | FBVideoEncoderOptionsFinalFrame
    timescale:1000
    roundingMethod:kCMTimeRoundingMethod_QuickTime
    filePath:FBVideoEncoderConfiguration.defaultVideoPath
    fileType:AVFileTypeQuickTimeMovie];
}

- (instancetype)init
{
  return [self
    initWithOptions:FBVideoEncoderOptionsImmediateFrameStart | FBVideoEncoderOptionsFinalFrame
    timescale:1000
    roundingMethod:kCMTimeRoundingMethod_RoundTowardZero
    filePath:FBVideoEncoderConfiguration.defaultVideoPath
    fileType:AVFileTypeMPEG4];
}

- (instancetype)initWithOptions:(FBVideoEncoderOptions)options timescale:(CMTimeScale)timescale roundingMethod:(CMTimeRoundingMethod)roundingMethod filePath:(NSString *)filePath fileType:(NSString *)fileType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _options = options;
  _timescale = timescale;
  _roundingMethod = roundingMethod;
  _filePath = filePath;
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
  return (NSUInteger) self.options ^ (NSUInteger) self.timescale ^ (NSUInteger) self.roundingMethod ^ self.filePath.hash ^ self.fileType.hash;
}

- (BOOL)isEqual:(FBVideoEncoderConfiguration *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }

  return (self.options == configuration.options) &&
         (self.timescale == configuration.timescale) &&
         (self.roundingMethod == configuration.roundingMethod) &&
         (self.filePath == configuration.filePath || [self.filePath isEqualToString:configuration.filePath]) &&
         (self.fileType == configuration.fileType || [self.fileType isEqualToString:configuration.fileType]);
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)decoder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _options = [[decoder decodeObjectOfClass:NSNumber.class forKey:NSStringFromSelector(@selector(options))] unsignedIntegerValue];
  _timescale = [decoder decodeInt32ForKey:NSStringFromSelector(@selector(timescale))];
  _roundingMethod = [[decoder decodeObjectOfClass:NSNumber.class forKey:NSStringFromSelector(@selector(roundingMethod))] unsignedIntValue];
  _filePath = [decoder decodeObjectOfClass:NSString.class forKey:NSStringFromSelector(@selector(filePath))];
  _fileType = [decoder decodeObjectOfClass:NSString.class forKey:NSStringFromSelector(@selector(fileType))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:@(self.options) forKey:NSStringFromSelector(@selector(options))];
  [coder encodeInt32:self.timescale forKey:NSStringFromSelector(@selector(timescale))];
  [coder encodeObject:@(self.roundingMethod) forKey:NSStringFromSelector(@selector(roundingMethod))];
  [coder encodeObject:self.filePath forKey:NSStringFromSelector(@selector(filePath))];
  [coder encodeObject:self.fileType forKey:NSStringFromSelector(@selector(fileType))];
}

#pragma mark FBJSONSerializable

static NSString *const KeyOptions = @"options";
static NSString *const KeyTimescale = @"timescale";
static NSString *const KeyRoundingMethod = @"rounding_method";
static NSString *const KeyFilePath = @"file_path";
static NSString *const KeyFileType = @"file_type";

- (id)jsonSerializableRepresentation
{
  return @{
    KeyOptions : [FBVideoEncoderConfiguration stringsFromVideoOptions:self.options],
    KeyTimescale : @(self.timescale),
    KeyRoundingMethod : @(self.roundingMethod),
    KeyFilePath : self.filePath,
    KeyFileType : self.fileType ?: NSNull.null,
  };
}

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not an Dictionary<String, Any>", json]
      fail:error];
  }
  NSArray<NSString *> *optionStrings = json[KeyOptions];
  FBVideoEncoderOptions options = 0;
  if (![FBCollectionInformation isArrayHeterogeneous:optionStrings withClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not an Array<String> for %@", optionStrings, KeyOptions]
      fail:error];
  }
  options = [FBVideoEncoderConfiguration videoOptionsFromStrings:optionStrings];
  NSNumber *timescaleNumber = json[KeyTimescale];
  if (![timescaleNumber isKindOfClass:NSNumber.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not an Number for %@", timescaleNumber, KeyTimescale]
      fail:error];
  }
  NSNumber *roundingMethodNumber = json[KeyRoundingMethod];
  if (![roundingMethodNumber isKindOfClass:NSNumber.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not an Number for %@", roundingMethodNumber, KeyRoundingMethod]
      fail:error];
  }
  NSString *filePath = json[KeyFilePath];
  if (![filePath isKindOfClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not an String for %@", filePath, KeyFilePath]
      fail:error];
  }
  NSString *fileType = [FBCollectionOperations nullableValueForDictionary:json key:KeyFileType];
  if (fileType && ![fileType isKindOfClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not an String for %@", fileType, KeyFileType]
      fail:error];
  }

  return [[FBVideoEncoderConfiguration alloc]
    initWithOptions:options
    timescale:timescaleNumber.intValue
    roundingMethod:roundingMethodNumber.unsignedIntValue
    filePath:filePath
    fileType:fileType];
}

#pragma mark FBDebugDescribeable

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Options %@ | Timescale %d | Rounding Method %d | File Path %@ | File Type %@",
    [FBVideoEncoderConfiguration stringsFromVideoOptions:self.options],
    self.timescale,
    self.roundingMethod,
    self.filePath,
    self.fileType
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

#pragma mark Autorecord

+ (instancetype)withOptions:(FBVideoEncoderOptions)options
{
  return [self.defaultConfiguration withOptions:options];
}

- (instancetype)withOptions:(FBVideoEncoderOptions)options
{
  return [[self.class alloc] initWithOptions:options timescale:self.timescale roundingMethod:self.roundingMethod filePath:self.filePath fileType:self.fileType];
}

#pragma mark Timescale

+ (instancetype)withTimescale:(CMTimeScale)timescale
{
  return [self.defaultConfiguration withTimescale:timescale];
}

- (instancetype)withTimescale:(CMTimeScale)timescale
{
  return [[self.class alloc] initWithOptions:self.options timescale:timescale roundingMethod:self.roundingMethod filePath:self.filePath fileType:self.fileType];
}

#pragma mark Rounding

+ (instancetype)withRoundingMethod:(CMTimeRoundingMethod)roundingMethod
{
  return [self.defaultConfiguration withRoundingMethod:roundingMethod];
}

- (instancetype)withRoundingMethod:(CMTimeRoundingMethod)roundingMethod
{
  return [[self.class alloc] initWithOptions:self.options timescale:self.timescale roundingMethod:roundingMethod filePath:self.filePath fileType:self.fileType];
}

#pragma mark File Path

+ (instancetype)withFilePath:(NSString *)filePath
{
  return [self.defaultConfiguration withFilePath:filePath];
}

- (instancetype)withFilePath:(NSString *)filePath
{
  return [[self.class alloc] initWithOptions:self.options timescale:self.timescale roundingMethod:self.roundingMethod filePath:filePath fileType:self.fileType];
}

+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic
{
  return [self.defaultConfiguration withDiagnostic:diagnostic];
}

- (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic
{
  FBDiagnosticBuilder *builder = [FBDiagnosticBuilder builderWithDiagnostic:diagnostic];
  return [[self.class alloc] initWithOptions:self.options timescale:self.timescale roundingMethod:self.roundingMethod filePath:builder.createPath fileType:self.fileType];
}

#pragma mark File Type

+ (instancetype)withFileType:(NSString *)fileType
{
  return [self.defaultConfiguration withFileType:fileType];
}

- (instancetype)withFileType:(NSString *)fileType
{
  return [[self.class alloc] initWithOptions:self.options timescale:self.timescale roundingMethod:self.roundingMethod filePath:self.filePath fileType:fileType];
}

#pragma mark Private

static NSString *const VideoOptionStringAutorecord = @"Autorecord";
static NSString *const VideoOptionStringImmediateFrameStart = @"Immediate Frame Start";
static NSString *const VideoOptionStringFinalFrame = @"Final Frame";

+ (NSArray<NSString *> *)stringsFromVideoOptions:(FBVideoEncoderOptions)options
{
  NSMutableArray<NSString *> *strings = [NSMutableArray array];
  if ((options & FBVideoEncoderOptionsAutorecord) == FBVideoEncoderOptionsAutorecord) {
    [strings addObject:VideoOptionStringAutorecord];
  }
  if ((options & FBVideoEncoderOptionsImmediateFrameStart) == FBVideoEncoderOptionsImmediateFrameStart) {
    [strings addObject:VideoOptionStringImmediateFrameStart];
  }
  if ((options & FBVideoEncoderOptionsFinalFrame) == FBVideoEncoderOptionsFinalFrame) {
    [strings addObject:VideoOptionStringFinalFrame];
  }
  return [strings copy];
}

+ (FBVideoEncoderOptions)videoOptionsFromStrings:(NSArray<NSString *> *)strings
{
  FBVideoEncoderOptions options = 0;
  for (NSString *optionString in strings) {
    if ([optionString isEqualToString:VideoOptionStringAutorecord]) {
      options = options | FBVideoEncoderOptionsAutorecord;
    } else if ([optionString isEqualToString:VideoOptionStringImmediateFrameStart]) {
      options = options | FBVideoEncoderOptionsImmediateFrameStart;
    } else if ([optionString isEqualToString:VideoOptionStringFinalFrame]) {
      options = options | FBVideoEncoderOptionsFinalFrame;
    }
  }
  return options;
}

@end

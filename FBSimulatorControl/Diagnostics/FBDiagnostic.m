/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDiagnostic.h"

#import <objc/runtime.h>

@interface FBDiagnostic ()

@property (nonatomic, copy, readwrite) NSString *shortName;
@property (nonatomic, copy, readwrite) NSString *fileType;
@property (nonatomic, copy, readwrite) NSString *humanReadableName;
@property (nonatomic, copy, readwrite) NSString *storageDirectory;
@property (nonatomic, copy, readwrite) NSString *destination;

@property (nonatomic, copy, readwrite) NSData *backingData;
@property (nonatomic, copy, readwrite) NSString *backingString;
@property (nonatomic, copy, readwrite) NSString *backingFilePath;

@end

/**
 A representation of a Diagnostic, backed by NSData.
 */
@interface FBDiagnostic_Data : FBDiagnostic

@end

/**
 A representation of a Diagnostic, backed by an NSString.
 */
@interface FBDiagnostic_String : FBDiagnostic

@end

/**
 A representation of a Diagnostic, backed by a File Path.
 */
@interface FBDiagnostic_Path : FBDiagnostic

@end

/**
 A representation of a Diagnostic, where the log is known to not exist.
 */
@interface FBDiagnostic_Empty : FBDiagnostic

@end

@implementation FBDiagnostic

#pragma mark Initializers

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _storageDirectory = [FBDiagnostic defaultStorageDirectory];

  return self;
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _shortName = [coder decodeObjectForKey:NSStringFromSelector(@selector(shortName))];
  _fileType = [coder decodeObjectForKey:NSStringFromSelector(@selector(fileType))];
  _humanReadableName = [coder decodeObjectForKey:NSStringFromSelector(@selector(humanReadableName))];
  _storageDirectory = [coder decodeObjectForKey:NSStringFromSelector(@selector(storageDirectory))];
  _destination = [coder decodeObjectForKey:NSStringFromSelector(@selector(destination))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.shortName forKey:NSStringFromSelector(@selector(shortName))];
  [coder encodeObject:self.fileType forKey:NSStringFromSelector(@selector(fileType))];
  [coder encodeObject:self.humanReadableName forKey:NSStringFromSelector(@selector(humanReadableName))];
  [coder encodeObject:self.storageDirectory forKey:NSStringFromSelector(@selector(storageDirectory))];
  [coder encodeObject:self.destination forKey:NSStringFromSelector(@selector(destination))];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBDiagnostic *diagnostic = [self.class new];
  diagnostic.shortName = self.shortName;
  diagnostic.fileType = self.fileType;
  diagnostic.humanReadableName = self.humanReadableName;
  diagnostic.storageDirectory = self.storageDirectory;
  diagnostic.destination = self.destination;
  return diagnostic;
}

#pragma mark Public API

- (BOOL)hasLogContent
{
  return NO;
}

- (BOOL)writeOutToPath:(NSString *)path error:(NSError **)error
{
  return NO;
}

#pragma mark Private

+ (NSString *)defaultStorageDirectory
{
  return [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
}

- (NSString *)temporaryFilePath
{
  NSString *filename = self.shortName ?: NSUUID.UUID.UUIDString;
  filename = [filename stringByAppendingPathExtension:self.fileType ?: @"unknown_log"];

  NSString *storageDirectory = self.storageDirectory;
  [NSFileManager.defaultManager createDirectoryAtPath:storageDirectory withIntermediateDirectories:YES attributes:nil error:nil];

  return [storageDirectory stringByAppendingPathComponent:filename];
}

#pragma mark FBJSONSerializationDescribeable

- (NSDictionary *)jsonSerializableRepresentation
{
  NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
  if (self.shortName) {
    dictionary[@"short_name"] = self.shortName;
  }
  if (self.humanReadableName) {
    dictionary[@"human_name"] = self.humanReadableName;
  }
  if (self.fileType) {
    dictionary[@"file_type"] = self.fileType;
  }
  return dictionary;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return self.shortDescription;
}

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"%@ | Human Name '%@' | File Type '%@'",
    self.shortDescription,
    self.humanReadableName,
    self.fileType
  ];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Short Name '%@' | Content %d",
    self.shortName,
    self.hasLogContent
  ];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBDiagnostic *)diagnostic
{
  if ([diagnostic isMemberOfClass:self.class]) {
    return NO;
  }

  return (self.shortName == diagnostic.shortName || [self.shortName isEqualToString:diagnostic.shortName]) &&
         (self.fileType == diagnostic.fileType || [self.fileType isEqualToString:diagnostic.fileType]) &&
         (self.humanReadableName == diagnostic.humanReadableName || [self.humanReadableName isEqualToString:diagnostic.humanReadableName]) &&
         (self.storageDirectory == diagnostic.storageDirectory || [self.storageDirectory isEqualToString:diagnostic.storageDirectory]) &&
         (self.destination == diagnostic.destination || [self.destination isEqualToString:diagnostic.destination]);
}

- (NSUInteger)hash
{
  return self.shortName.hash ^ self.fileType.hash ^ self.humanReadableName.hash ^ self.storageDirectory.hash ^ self.destination.hash;
}

@end

@implementation FBDiagnostic_Data

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (!self) {
    return nil;
  }

  self.backingData = [coder decodeObjectForKey:NSStringFromSelector(@selector(backingData))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [super encodeWithCoder:coder];
  [coder encodeObject:self.backingData forKey:NSStringFromSelector(@selector(backingData))];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBDiagnostic_Data *log = [super copyWithZone:zone];
  log.backingData = self.backingData;
  return log;
}

#pragma mark Public API

- (NSData *)asData
{
  return self.backingData;
}

- (NSString *)asString
{
  if (!self.backingString) {
    self.backingString = [[NSString alloc] initWithData:self.backingData encoding:NSUTF8StringEncoding];
  }
  return self.backingString;
}

- (NSString *)asPath
{
  if (!self.backingFilePath) {
    NSString *path = [self temporaryFilePath];
    if ([self.backingData writeToFile:path atomically:YES]) {
      self.backingFilePath = path;
    }
  }
  return self.backingFilePath;
}

- (BOOL)hasLogContent
{
  return self.backingData.length >= 1;
}

- (BOOL)writeOutToPath:(NSString *)path error:(NSError **)error
{
  return [self.backingData writeToFile:path options:0 error:error];
}

#pragma mark FBJSONSerializationDescribeable

- (NSDictionary *)jsonSerializableRepresentation
{
  NSMutableDictionary *dictionary = [[super jsonSerializableRepresentation] mutableCopy];
  NSString *base64String = [self.backingData base64EncodedStringWithOptions:0];
  if (base64String) {
    dictionary[@"data"] = base64String;
  }
  return dictionary;
}

#pragma mark FBDebugDescribable

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Data Log %@",
    [super shortDescription]
  ];
}

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"Data Log %@",
    [super debugDescription]
  ];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBDiagnostic_Data *)diagnostic
{
  if ([super isEqual:diagnostic]) {
    return NO;
  }

  return self.backingData == diagnostic.backingData || [self.backingData isEqualToData:diagnostic.backingData];
}

- (NSUInteger)hash
{
  return super.hash ^ self.backingData.hash;
}

@end

@implementation FBDiagnostic_String

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (!self) {
    return nil;
  }

  self.backingString = [coder decodeObjectForKey:NSStringFromSelector(@selector(backingString))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [super encodeWithCoder:coder];
  [coder encodeObject:self.backingString forKey:NSStringFromSelector(@selector(backingString))];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBDiagnostic_String *log = [super copyWithZone:zone];
  log.backingString = self.backingString;
  return log;
}

#pragma mark Public API

- (NSData *)asData
{
  if (!self.backingData) {
    self.backingData = [self.backingString dataUsingEncoding:NSUTF8StringEncoding];
  }
  return self.backingData;
}

- (NSString *)asString
{
  return self.backingString;
}

- (NSString *)asPath
{
  if (!self.backingFilePath) {
    NSString *path = [self temporaryFilePath];
    if ([self.backingString writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
      self.backingFilePath = path;
    }
  }
  return self.backingFilePath;
}

- (BOOL)hasLogContent
{
  return self.backingString.length >= 1;
}

- (BOOL)writeOutToPath:(NSString *)path error:(NSError **)error
{
  return [self.backingString writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:error];
}

#pragma mark FBJSONSerializationDescribeable

- (NSDictionary *)jsonSerializableRepresentation
{
  NSMutableDictionary *dictionary = [[super jsonSerializableRepresentation] mutableCopy];
  dictionary[@"contents"] = self.backingString;
  return dictionary;
}

#pragma mark FBDebugDescribable

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"String Log %@",
    [super shortDescription]
  ];
}

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"String Log %@ | Content '%@'",
    [super debugDescription],
    self.asString
  ];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBDiagnostic_String *)diagnostic
{
  if ([super isEqual:diagnostic]) {
    return NO;
  }

  return self.backingString == diagnostic.backingString || [self.backingString isEqualToString:diagnostic.backingString];
}

- (NSUInteger)hash
{
  return super.hash ^ self.backingString.hash;
}

@end

@implementation FBDiagnostic_Path

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (!self) {
    return nil;
  }

  self.backingFilePath = [coder decodeObjectForKey:NSStringFromSelector(@selector(backingFilePath))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [super encodeWithCoder:coder];
  [coder encodeObject:self.backingFilePath forKey:NSStringFromSelector(@selector(backingFilePath))];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBDiagnostic_Path *log = [super copyWithZone:zone];
  log.backingFilePath = self.backingFilePath;
  return log;
}

#pragma mark Public API

- (NSData *)asData
{
  if (!self.backingData) {
    self.backingData = [[NSData alloc] initWithContentsOfFile:self.backingFilePath];
  }
  return self.backingData;
}

- (NSString *)asString
{
  if (!self.backingString) {
    self.backingString = [[NSString alloc] initWithContentsOfFile:self.backingFilePath usedEncoding:nil error:nil];
  }
  return self.backingString;
}

- (NSString *)asPath
{
  return self.backingFilePath;
}

- (BOOL)hasLogContent
{
  NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:self.backingFilePath error:nil];
  return attributes[NSFileSize] && [attributes[NSFileSize] unsignedLongLongValue] > 0;
}

- (BOOL)writeOutToPath:(NSString *)path error:(NSError **)error
{
  if ([self.backingFilePath.stringByStandardizingPath isEqualToString:self.backingFilePath.stringByStandardizingPath]) {
    return YES;
  }
  return [NSFileManager.defaultManager copyItemAtPath:self.backingFilePath toPath:path error:error];
}

#pragma mark FBJSONSerializationDescribeable

- (NSDictionary *)jsonSerializableRepresentation
{
  NSMutableDictionary *dictionary = [[super jsonSerializableRepresentation] mutableCopy];
  dictionary[@"location"] = self.backingFilePath;
  return dictionary;
}


#pragma mark FBDebugDescribeable

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Path Log %@ | Path %@",
    [super shortDescription],
    self.asPath
  ];
}

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"Path Log %@ | Path %@",
    [super debugDescription],
    self.asPath
  ];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBDiagnostic_Path *)diagnostic
{
  if ([super isEqual:diagnostic]) {
    return NO;
  }

  return self.backingFilePath == diagnostic.backingFilePath || [self.backingFilePath isEqualToString:diagnostic.backingFilePath];
}

- (NSUInteger)hash
{
  return super.hash ^ self.backingFilePath.hash;
}

@end

@implementation FBDiagnostic_Empty

- (NSData *)asData
{
  return nil;
}

- (NSString *)asString
{
  return nil;
}

- (NSString *)asPath
{
  return nil;
}

@end

@interface FBDiagnosticBuilder ()

@property (nonatomic, copy) FBDiagnostic *diagnostic;

@end

@implementation FBDiagnosticBuilder : NSObject

+ (instancetype)builder
{
  return [self builderWithDiagnostic:nil];
}

+ (instancetype)builderWithDiagnostic:(FBDiagnostic *)diagnostic
{
  return [[FBDiagnosticBuilder new] updateDiagnostic:[diagnostic copy] ?: [FBDiagnostic_Empty new]];
}

- (instancetype)updateDiagnostic:(FBDiagnostic *)diagnostic
{
  if (!diagnostic) {
    return self;
  }
  self.diagnostic = diagnostic;
  return self;
}

- (instancetype)updateShortName:(NSString *)shortName
{
  self.diagnostic.shortName = shortName;
  return self;
}

- (instancetype)updateFileType:(NSString *)fileType
{
  self.diagnostic.fileType = fileType;
  return self;
}

- (instancetype)updateHumanReadableName:(NSString *)humanReadableName
{
  self.diagnostic.humanReadableName = humanReadableName;
  return self;
}

- (instancetype)updateStorageDirectory:(NSString *)storageDirectory
{
  if (![NSFileManager.defaultManager fileExistsAtPath:storageDirectory]) {
    if (![NSFileManager.defaultManager createDirectoryAtPath:storageDirectory withIntermediateDirectories:YES attributes:nil error:nil]) {
      return self;
    }
  }
  self.diagnostic.storageDirectory = storageDirectory;
  return self;
}

- (instancetype)updateDestination:(NSString *)destination
{
  self.diagnostic.destination = destination;
  return self;
}

- (instancetype)updateData:(NSData *)data
{
  [self flushBackingStore];
  if (!data) {
    return self;
  }
  object_setClass(self.diagnostic, FBDiagnostic_Data.class);
  self.diagnostic.backingData = data;
  return self;
}

- (instancetype)updateString:(NSString *)string
{
  [self flushBackingStore];
  if (!string) {
    return self;
  }
  object_setClass(self.diagnostic, FBDiagnostic_String.class);
  self.diagnostic.backingString = string;
  return self;
}

- (instancetype)updatePath:(NSString *)path
{
  [self flushBackingStore];
  if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
    return self;
  }
  object_setClass(self.diagnostic, FBDiagnostic_Path.class);
  self.diagnostic.backingFilePath = path;
  self.diagnostic.fileType = [path pathExtension];
  return self;
}

- (NSString *)createPath
{
  return [self.diagnostic temporaryFilePath];
}

- (instancetype)updatePathFromBlock:( BOOL (^)(NSString *path) )block
{
  NSString *path = [self createPath];
  if (!block(path)) {
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    [self flushBackingStore];
  }
  return [self updatePath:path];
}

- (FBDiagnostic *)build
{
  return self.diagnostic;
}

#pragma mark Private

- (void)flushBackingStore
{
  self.diagnostic.backingData = nil;
  self.diagnostic.backingString = nil;
  self.diagnostic.backingFilePath = nil;
  object_setClass(self.diagnostic, FBDiagnostic_Empty.class);
}

+ (NSSet *)defaultStringBackedPathExtensions
{
  static dispatch_once_t onceToken;
  static NSSet *extensions;
  dispatch_once(&onceToken, ^{
    extensions = [NSSet setWithArray:@[@"txt", @"log", @""]];
  });
  return extensions;
}

@end

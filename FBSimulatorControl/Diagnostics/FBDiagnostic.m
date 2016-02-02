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

@property (nonatomic, copy, readwrite) NSData *logData;
@property (nonatomic, copy, readwrite) NSString *logString;
@property (nonatomic, copy, readwrite) NSString *logPath;

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

@end

@implementation FBDiagnostic_Data

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (!self) {
    return nil;
  }

  self.logData = [coder decodeObjectForKey:NSStringFromSelector(@selector(logData))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [super encodeWithCoder:coder];
  [coder encodeObject:self.logData forKey:NSStringFromSelector(@selector(logData))];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBDiagnostic_Data *log = [super copyWithZone:zone];
  log.logData = self.logData;
  return log;
}

#pragma mark Public API

- (NSData *)asData
{
  return self.logData;
}

- (NSString *)asString
{
  if (!self.logString) {
    self.logString = [[NSString alloc] initWithData:self.logData encoding:NSUTF8StringEncoding];
  }
  return self.logString;
}

- (NSString *)asPath
{
  if (!self.logPath) {
    NSString *path = [self temporaryFilePath];
    if ([self.logData writeToFile:path atomically:YES]) {
      self.logPath = path;
    }
  }
  return self.logPath;
}

- (BOOL)hasLogContent
{
  return self.logData.length >= 1;
}

- (BOOL)writeOutToPath:(NSString *)path error:(NSError **)error
{
  return [self.logData writeToFile:path options:0 error:error];
}

#pragma mark FBJSONSerializationDescribeable

- (NSDictionary *)jsonSerializableRepresentation
{
  NSMutableDictionary *dictionary = [[super jsonSerializableRepresentation] mutableCopy];
  NSString *base64String = [self.logData base64EncodedStringWithOptions:0];
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

@end

@implementation FBDiagnostic_String

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (!self) {
    return nil;
  }

  self.logString = [coder decodeObjectForKey:NSStringFromSelector(@selector(logString))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [super encodeWithCoder:coder];
  [coder encodeObject:self.logString forKey:NSStringFromSelector(@selector(logString))];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBDiagnostic_String *log = [super copyWithZone:zone];
  log.logString = self.logString;
  return log;
}

#pragma mark Public API

- (NSData *)asData
{
  if (!self.logData) {
    self.logData = [self.logString dataUsingEncoding:NSUTF8StringEncoding];
  }
  return self.logData;
}

- (NSString *)asString
{
  return self.logString;
}

- (NSString *)asPath
{
  if (!self.logPath) {
    NSString *path = [self temporaryFilePath];
    if ([self.logString writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
      self.logPath = path;
    }
  }
  return self.logPath;
}

- (BOOL)hasLogContent
{
  return self.logString.length >= 1;
}

- (BOOL)writeOutToPath:(NSString *)path error:(NSError **)error
{
  return [self.logString writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:error];
}

#pragma mark FBJSONSerializationDescribeable

- (NSDictionary *)jsonSerializableRepresentation
{
  NSMutableDictionary *dictionary = [[super jsonSerializableRepresentation] mutableCopy];
  dictionary[@"contents"] = self.logString;
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

@end

@implementation FBDiagnostic_Path

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (!self) {
    return nil;
  }

  self.logPath = [coder decodeObjectForKey:NSStringFromSelector(@selector(logPath))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [super encodeWithCoder:coder];
  [coder encodeObject:self.logPath forKey:NSStringFromSelector(@selector(logPath))];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBDiagnostic_Path *log = [super copyWithZone:zone];
  log.logPath = self.logPath;
  return log;
}

#pragma mark Public API

- (NSData *)asData
{
  if (!self.logData) {
    self.logData = [[NSData alloc] initWithContentsOfFile:self.logPath];
  }
  return self.logData;
}

- (NSString *)asString
{
  if (!self.logString) {
    self.logString = [[NSString alloc] initWithContentsOfFile:self.logPath usedEncoding:nil error:nil];
  }
  return self.logString;
}

- (NSString *)asPath
{
  return self.logPath;
}

- (NSDictionary *)jsonSerializableRepresentation
{
  NSMutableDictionary *dictionary = [[super jsonSerializableRepresentation] mutableCopy];
  dictionary[@"location"] = self.logPath;
  return dictionary;
}

- (BOOL)hasLogContent
{
  NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:self.logPath error:nil];
  return attributes[NSFileSize] && [attributes[NSFileSize] unsignedLongLongValue] > 0;
}

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

- (BOOL)writeOutToPath:(NSString *)path error:(NSError **)error
{
  return [NSFileManager.defaultManager copyItemAtPath:self.logPath toPath:path error:error];
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
  [self flushLogs];
  if (!data) {
    return self;
  }
  object_setClass(self.diagnostic, FBDiagnostic_Data.class);
  self.diagnostic.logData = data;
  return self;
}

- (instancetype)updateString:(NSString *)string
{
  [self flushLogs];
  if (!string) {
    return self;
  }
  object_setClass(self.diagnostic, FBDiagnostic_String.class);
  self.diagnostic.logString = string;
  return self;
}

- (instancetype)updatePath:(NSString *)path
{
  [self flushLogs];
  if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
    return self;
  }
  object_setClass(self.diagnostic, FBDiagnostic_Path.class);
  self.diagnostic.logPath = path;
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
    [self flushLogs];
  }
  return [self updatePath:path];
}

- (FBDiagnostic *)build
{
  return self.diagnostic;
}

#pragma mark Private

- (void)flushLogs
{
  self.diagnostic.logData = nil;
  self.diagnostic.logString = nil;
  self.diagnostic.logPath = nil;
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

/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDiagnostic.h"

#import <objc/runtime.h>

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"

@interface FBDiagnostic ()

@property (nonatomic, copy, readwrite) FBDiagnosticName shortName;
@property (nonatomic, copy, readwrite) NSString *fileType;
@property (nonatomic, copy, readwrite) NSString *humanReadableName;
@property (nonatomic, copy, readwrite) NSString *storageDirectory;
@property (nonatomic, copy, readwrite) NSString *destination;

@property (nonatomic, copy, readwrite) NSData *backingData;
@property (nonatomic, copy, readwrite) NSString *backingString;
@property (nonatomic, copy, readwrite) NSString *backingFilePath;
@property (nonatomic, copy, readwrite) id backingJSON;

@end

/**
 A representation of a Diagnostic, backed by NSData.
 */
@interface FBDiagnostic_Data : FBDiagnostic

+ (NSData *)dataFromJSON:(NSDictionary *)json error:(NSError **)error;

@end

/**
 A representation of a Diagnostic, backed by an NSString.
 */
@interface FBDiagnostic_String : FBDiagnostic

+ (NSString *)stringFromJSON:(NSDictionary *)json error:(NSError **)error;

@end

/**
 A representation of a Diagnostic, backed by a File Path.
 */
@interface FBDiagnostic_Path : FBDiagnostic

+ (NSString *)pathFromJSON:(NSDictionary *)json error:(NSError **)error;

@end

/**
 A representation of a Diagnostic, backed by JSON.
 */
@interface FBDiagnostic_JSON : FBDiagnostic

+ (id)objectFromJSON:(NSDictionary *)json error:(NSError **)error;

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

- (NSData *)asData
{
  return self.backingData;
}

- (NSString *)asString
{
  return self.backingString;
}

- (NSString *)asPath
{
  return self.backingFilePath;
}

- (id)asJSON
{
  return self.backingJSON;
}

- (BOOL)hasLogContent
{
  return NO;
}

- (BOOL)isSearchableAsText
{
  return self.asString != nil;
}

- (BOOL)writeOutToFilePath:(NSString *)path error:(NSError **)error
{
  return NO;
}

- (NSString *)writeOutToDirectory:(NSString *)directory error:(NSError **)error
{
  BOOL isDirectory = NO;
  if (![NSFileManager.defaultManager fileExistsAtPath:directory isDirectory:&isDirectory]) {
    return [[FBControlCoreError describeFormat:@"Directory %@ does not exist", directory] fail:error];
  }
  if (!isDirectory) {
    return [[FBControlCoreError describeFormat:@"Path %@ is not a directory", directory] fail:error];
  }

  NSString *filePath = [directory stringByAppendingPathComponent:self.inferredFilename];
  if (![self writeOutToFilePath:filePath error:error]) {
    return nil;
  }
  return filePath;
}

#pragma mark Private

+ (NSString *)defaultStorageDirectory
{
  return [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
}

- (NSString *)inferredFilename
{
  NSString *filename = self.shortName ?: NSUUID.UUID.UUIDString;
  return [filename stringByAppendingPathExtension:self.fileType ?: @"unknown_log"];
}

- (NSString *)temporaryFilePath
{
  NSString *filename = self.shortName ?: NSUUID.UUID.UUIDString;
  filename = [filename stringByAppendingPathExtension:self.fileType ?: @"unknown_log"];

  NSString *storageDirectory = self.storageDirectory;
  [NSFileManager.defaultManager createDirectoryAtPath:storageDirectory withIntermediateDirectories:YES attributes:nil error:nil];

  return [storageDirectory stringByAppendingPathComponent:filename];
}

#pragma mark JSON

+ (instancetype)inflateFromJSON:(NSDictionary *)json error:(NSError **)error
{
  if (![FBCollectionInformation isArrayHeterogeneous:json.allKeys withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ does not have string keys", json] fail:error];
  }
  NSString *shortName = json[@"short_name"];
  if (!shortName) {
    return [[FBControlCoreError describeFormat:@"%@ should exist for for 'short_name'", shortName] fail:error];
  }
  NSString *humanReadableName = json[@"human_name"];
  NSString *fileType = json[@"file_type"];
  FBDiagnosticBuilder *builder = [[[[FBDiagnosticBuilder builder]
    updateShortName:shortName]
    updateHumanReadableName:humanReadableName]
    updateFileType:fileType];

  NSData *data = [FBDiagnostic_Data dataFromJSON:json error:nil];
  if (data) {
    return [[builder updateData:data] build];
  }
  NSString *string = [FBDiagnostic_String stringFromJSON:json error:nil];
  if (string) {
    return [[builder updateString:string] build];
  }
  NSString *path = [FBDiagnostic_Path pathFromJSON:json error:nil];
  if (path) {
    return [[builder updatePath:path] build];
  }
  id object = [FBDiagnostic_JSON objectFromJSON:json error:nil];
  if (object) {
    return [[builder updateJSON:object] build];
  }
  return [builder build];
}

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

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBDiagnostic_Data *log = [super copyWithZone:zone];
  log.backingData = self.backingData;
  return log;
}

#pragma mark Public API

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
    if (![self writeOutToFilePath:path error:nil]) {
      return nil;
    }
    self.backingFilePath = path;
  }
  return self.backingFilePath;
}

- (id)asJSON
{
  if (!self.backingJSON) {
    self.backingJSON = [NSJSONSerialization JSONObjectWithData:self.backingData options:0 error:nil];
  }
  return self.backingJSON;
}

- (BOOL)hasLogContent
{
  return self.backingData.length >= 1;
}

- (BOOL)writeOutToFilePath:(NSString *)path error:(NSError **)error
{
  if ([NSFileManager.defaultManager fileExistsAtPath:path] && ![NSFileManager.defaultManager removeItemAtPath:path error:error]) {
    return NO;
  }
  return [self.backingData writeToFile:path options:0 error:error];
}

#pragma mark JSON

+ (NSData *)dataFromJSON:(NSDictionary *)json error:(NSError **)error
{
  NSString *base64String = json[@"data"];
  if (![base64String isKindOfClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a string for 'data'", base64String] fail:error];
  }
  NSData *data = [[NSData alloc] initWithBase64EncodedString:base64String options:0];
  if (!data) {
    return [[FBControlCoreError describe:@"base64 encoded string could not be decoded"] fail:error];
  }
  return data;
}

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

- (NSString *)asPath
{
  if (!self.backingFilePath) {
    NSString *path = [self temporaryFilePath];
    if (![self writeOutToFilePath:path error:nil]) {
      return nil;
    }
    self.backingFilePath = path;
  }
  return self.backingFilePath;
}

- (id)asJSON
{
  if (!self.backingJSON) {
    if (!self.asData) {
      return nil;
    }
    self.backingJSON = [NSJSONSerialization JSONObjectWithData:self.asData options:0 error:nil];
  }
  return self.backingJSON;
}

- (BOOL)hasLogContent
{
  return self.backingString.length >= 1;
}

- (BOOL)isSearchableAsText
{
  return YES;
}

- (BOOL)writeOutToFilePath:(NSString *)path error:(NSError **)error
{
  if ([NSFileManager.defaultManager fileExistsAtPath:path] && ![NSFileManager.defaultManager removeItemAtPath:path error:error]) {
    return NO;
  }
  return [self.backingString writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

#pragma mark JSON

+ (NSString *)stringFromJSON:(NSDictionary *)json error:(NSError **)error
{
  NSString *string = json[@"contents"];
  if (![string isKindOfClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a string for 'contents'", string] fail:error];
  }
  return string;
}

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
  return [[NSData alloc] initWithContentsOfFile:self.backingFilePath];
}

- (NSString *)asString
{
  return [[NSString alloc] initWithContentsOfFile:self.backingFilePath usedEncoding:nil error:nil];
}

- (id)asJSON
{
  NSInputStream *inputStream = [NSInputStream inputStreamWithFileAtPath:self.backingFilePath];
  [inputStream open];
  id json = [NSJSONSerialization JSONObjectWithStream:inputStream options:0 error:nil];
  [inputStream close];
  return json;
}

- (BOOL)hasLogContent
{
  NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:self.backingFilePath error:nil];
  return attributes[NSFileSize] && [attributes[NSFileSize] unsignedLongLongValue] > 0;
}

- (BOOL)writeOutToFilePath:(NSString *)path error:(NSError **)error
{
  if ([NSFileManager.defaultManager fileExistsAtPath:path] && ![NSFileManager.defaultManager removeItemAtPath:path error:error]) {
    return NO;
  }
  return [NSFileManager.defaultManager copyItemAtPath:self.backingFilePath toPath:path error:error];
}

#pragma mark JSON

+ (NSString *)pathFromJSON:(NSDictionary *)json error:(NSError **)error
{
  NSString *path = json[@"location"];
  if (![path isKindOfClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a string for 'path'", path] fail:error];
  }
  return path;
}

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

@implementation FBDiagnostic_JSON

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBDiagnostic_JSON *log = [super copyWithZone:zone];
  log.backingJSON = self.backingJSON;
  return log;
}

#pragma mark Public API

- (NSData *)asData
{
  if (!self.backingData) {
    self.backingData = [NSJSONSerialization dataWithJSONObject:self.backingJSON options:NSJSONWritingPrettyPrinted error:nil];
  }
  return self.backingData;
}

- (NSString *)asString
{
  if (!self.backingString) {
    NSData *data = self.asData;
    if (!data) {
      return nil;
    }
    self.backingString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  }
  return self.backingString;
}

- (NSString *)asPath
{
  if (!self.backingFilePath) {
    NSString *path = [self temporaryFilePath];
    if (![self writeOutToFilePath:path error:nil]) {
      return nil;
    }
    self.backingFilePath = path;
  }
  return self.backingFilePath;
}

- (BOOL)hasLogContent
{
  return self.backingJSON != nil;
}

- (BOOL)writeOutToFilePath:(NSString *)path error:(NSError **)error
{
  if ([NSFileManager.defaultManager fileExistsAtPath:path] && ![NSFileManager.defaultManager removeItemAtPath:path error:error]) {
    return NO;
  }

  NSOutputStream *outputStream = [NSOutputStream outputStreamToFileAtPath:path append:NO];
  [outputStream open];
  NSInteger bytesWritten = [NSJSONSerialization writeJSONObject:self.backingJSON toStream:outputStream options:NSJSONWritingPrettyPrinted error:nil];
  [outputStream close];
  return bytesWritten > 0;
}

#pragma mark JSON

+ (id)objectFromJSON:(NSDictionary *)json error:(NSError **)error
{
  id object = json[@"object"];
  if (!object) {
    return [[FBControlCoreError describe:@"'object' does not exist"] fail:error];
  }
  return object;
}

- (NSDictionary *)jsonSerializableRepresentation
{
  NSMutableDictionary *dictionary = [[super jsonSerializableRepresentation] mutableCopy];
  dictionary[@"object"] = self.backingJSON;
  return dictionary;
}

#pragma mark FBDebugDescribeable

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"JSON Log %@ | Value %@",
    [super shortDescription],
    self.backingJSON
  ];
}

- (NSString *)debugDescription
{
  return self.shortDescription;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBDiagnostic_JSON *)diagnostic
{
  if ([super isEqual:diagnostic]) {
    return NO;
  }

  return [self.backingJSON isEqual:diagnostic.backingJSON];
}

- (NSUInteger)hash
{
  return super.hash ^ [self.backingJSON hash];
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

- (id)asJSON
{
  return nil;
}

@end

@interface FBDiagnosticBuilder ()

@property (nonatomic, copy) FBDiagnostic *diagnostic;

@end

@implementation FBDiagnosticBuilder : NSObject

#pragma mark Initializers

+ (instancetype)builder
{
  return [[FBDiagnosticBuilder alloc] initWithDiagnostic:nil];
}

+ (instancetype)builderWithDiagnostic:(FBDiagnostic *)diagnostic
{
  return [[FBDiagnosticBuilder alloc] initWithDiagnostic:diagnostic];
}

- (instancetype)init
{
  return [self initWithDiagnostic:nil];
}

- (instancetype)initWithDiagnostic:(FBDiagnostic *)diagnostic
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _diagnostic = [diagnostic copy] ?: FBDiagnostic_Empty.new;

  return self;
}

#pragma mark Updates

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
  if (!self.diagnostic.shortName) {
    self.diagnostic.shortName = [[path lastPathComponent] stringByDeletingPathExtension];
  }
  if (!self.diagnostic.fileType) {
    self.diagnostic.fileType = [path pathExtension];
  }
  return self;
}

- (instancetype)updateJSON:(id)json
{
  json = [json conformsToProtocol:@protocol(FBJSONSerializable)] ? [json jsonSerializableRepresentation] : json;
  if (!json) {
    return self;
  }

  object_setClass(self.diagnostic, FBDiagnostic_JSON.class);
  self.diagnostic.backingJSON = json;
  self.diagnostic.fileType = @"json";
  return self;
}

- (NSString *)createPath
{
  return self.diagnostic.temporaryFilePath;
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

- (instancetype)updatePathFromDefaultLocation
{
  return [self updatePath:self.diagnostic.temporaryFilePath];
}

- (instancetype)readIntoMemory
{
  if (!self.diagnostic.backingFilePath || self.diagnostic.hasLogContent == NO) {
    return self;
  }
  id object = [self.diagnostic asJSON];
  if (object) {
    return [self updateJSON:object];
  }
  NSString *string = [self.diagnostic asString];
  if (string) {
    return [self updateString:string];
  }
  NSData *data = [self.diagnostic asData];
  if (data) {
    return [self updateData:data];
  }
  return self;
}

- (instancetype)writeOutToFile
{
  if (self.diagnostic.backingFilePath || self.diagnostic.hasLogContent == NO) {
    return self;
  }
  NSString *path = [self createPath];
  if (![self.diagnostic writeOutToFilePath:path error:nil]) {
    return self;
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
  self.diagnostic.backingJSON = nil;
  object_setClass(self.diagnostic, FBDiagnostic_Empty.class);
}

@end

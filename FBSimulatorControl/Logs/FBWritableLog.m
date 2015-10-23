/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBWritableLog.h"
#import "FBWritableLog+Private.h"

#import <objc/runtime.h>

@implementation FBWritableLog

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBWritableLog *log = [self.class new];
  log.shortName = self.shortName;
  log.fileType = self.fileType;
  log.destination = self.destination;
  log.humanReadableName = self.humanReadableName;
  log.logData = self.logData;
  log.logString = self.logString;
  log.logPath = self.logPath;
  return log;
}

- (NSData *)data
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be subclassed", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)string
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be subclassed", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)temporaryFilePath
{
  NSString *localUniqueID = self.shortName ?: [NSString stringWithFormat:@"%@_%@", NSUUID.UUID.UUIDString, @"unkown_log"];

  return [[NSTemporaryDirectory()
    stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@", NSProcessInfo.processInfo.globallyUniqueString, localUniqueID]]
    stringByAppendingPathExtension:self.fileType ?: @"unknown_log"];
}

@end

@implementation FBWritableLog_Data

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

@end

@implementation FBWritableLog_String

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

@end

@implementation FBWritableLog_Path

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

@end

@implementation FBWritableLog_Empty

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

@interface FBWritableLogBuilder ()

@property (nonatomic, copy) FBWritableLog *writableLog;

@end

@implementation FBWritableLogBuilder : NSObject

+ (instancetype)builder
{
  return [self builderWithWritableLog:[FBWritableLog_Empty new]];
}

+ (instancetype)builderWithWritableLog:(FBWritableLog *)writableLog
{
  FBWritableLogBuilder *builder = [FBWritableLogBuilder new];
  builder.writableLog = [writableLog copy];
  return builder;
}

- (instancetype)updateShortName:(NSString *)shortName
{
  self.writableLog.shortName = shortName;
  return self;
}

- (instancetype)updateFileType:(NSString *)fileType
{
  self.writableLog.fileType = fileType;
  return self;
}

- (instancetype)updateDestination:(NSString *)destination
{
  self.writableLog.destination = destination;
  return self;
}

- (instancetype)updateData:(NSData *)data
{
  [self flushLogs];
  if (!data) {
    return self;
  }
  object_setClass(self.writableLog, FBWritableLog_Data.class);
  self.writableLog.logData = data;
  return self;
}

- (instancetype)updateString:(NSString *)string
{
  [self flushLogs];
  if (!string) {
    return self;
  }
  object_setClass(self.writableLog, FBWritableLog_String.class);
  self.writableLog.logString = string;
  return self;
}

- (instancetype)updatePath:(NSString *)path
{
  [self flushLogs];
  if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
    return self;
  }
  object_setClass(self.writableLog, FBWritableLog_Path.class);
  self.writableLog.logPath = path;
  return self;
}

- (instancetype)updatePathFromBlock:( BOOL (^)(NSString *path) )block
{
  NSString *path = [self.writableLog temporaryFilePath];
  if (!block(path)) {
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    [self flushLogs];
  }
  return [self updatePath:path];
}

- (instancetype)updateHumanReadableName:(NSString *)humanReadableName
{
  self.writableLog.humanReadableName = humanReadableName;
  return self;
}

- (FBWritableLog *)build
{
  return self.writableLog;
}

#pragma mark Private

- (void)flushLogs
{
  self.writableLog.logData = nil;
  self.writableLog.logString = nil;
  self.writableLog.logPath = nil;
  object_setClass(self.writableLog, FBWritableLog_Empty.class);
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
